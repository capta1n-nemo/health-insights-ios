import SwiftUI
import InsightKit

/// Body measurements, by tape.
///
/// ## Why a tape entry exists at all, when a scanner is coming
///
/// It is not a stopgap. A tape is the **most accurate** circumference anybody
/// here will ever have — `BodyMeasurementProvenance` ranks it above LiDAR for
/// exactly that reason — and a reader who owns one should not be asked to stand
/// in front of a phone instead.
///
/// It also does something the scanner cannot do yet: it makes the whole chain
/// behind it real. `BuildAssessmentModel` and `SomatotypeModel` have shipped
/// with a `dimensions:` parameter that has never once been non-nil, because
/// nothing in the app could produce a waist. One tape measurement lights up the
/// RFM route on the Body Composition dial, the shoulder-to-waist lift on the
/// somatotype, a row in the Data tab and the body model — none of which needs
/// ARKit to be reviewable.
///
/// ## Waist first, and the rest optional
///
/// The sheet leads with the waist and marks it as the one that counts, because
/// it is: `BuildAssessmentModel` needs a waist and a height and nothing else,
/// and a form that asked for eleven measurements before it would do anything
/// would be abandoned at three.
struct BodyMeasurementsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var clothing: ScanConditions.Clothing = .minimal
    /// Whatever unit the toggle says, **as typed**, keyed by site **and side** —
    /// a paired site has two independent fields. Empty means "not measured",
    /// which is different from zero and must stay that way.
    ///
    /// ⚠️ Not centimetres any more, and the rename of this comment is the whole
    /// defect. Until 2026-08-07 the field drew a hard-coded `cm` and stored the
    /// typed number unchanged, so a reader with an inch tape recorded a
    /// 34-centimetre waist — which `BuildAssessmentModel` would then divide by
    /// their height and report as an extraordinary result rather than as an
    /// impossible one. `centimetres(_:_:)` is now the only path to storage.
    @State private var entries: [String: String] = [:]
    /// Paired sites get a second field when the reader wants both sides.
    @State private var showsSides: Set<BodySite> = []
    /// Shared with every other sheet that takes a measurement; see
    /// `MeasurementSystemStorage`.
    @AppStorage(MeasurementSystemStorage.key)
    private var unitPreference = MeasurementSystemPreference.automatic.rawValue

    /// The unit the fields are being typed in. `tapeLength` is centimetres in a
    /// metric system and inches in both the British and US ones — a UK reader's
    /// tape measure is very often imperial even though their thermometer is not.
    private var tapeUnit: DisplayUnit {
        MeasurementQuantity.tapeLength
            .unit(in: MeasurementSystemStorage.resolved(unitPreference)) ?? .centimetres
    }

    /// The order they are asked for: the one that scores, then trunk, then limbs.
    private static let order: [BodySite] = [.waist, .hip, .chest, .neck,
                                            .shoulderWidth, .thigh, .upperArm,
                                            .calf, .forearm, .underbust, .abdomen]

    private var measured: [BodyMeasurement] {
        var out: [BodyMeasurement] = []
        for site in Self.order {
            if site.isPaired, showsSides.contains(site) {
                if let left = centimetres(site, .left) {
                    out.append(.init(site: site, side: .left, centimetres: left))
                }
                if let right = centimetres(site, .right) {
                    out.append(.init(site: site, side: .right, centimetres: right))
                }
            } else if let single = centimetres(site, .centre) {
                out.append(.init(site: site, side: .centre, centimetres: single))
            }
        }
        return out
    }

    private func key(_ site: BodySite, _ side: BodySide) -> String {
        "\(site.rawValue).\(side.rawValue)"
    }

    /// What the reader typed, in the unit the toggle is showing.
    private func typed(_ site: BodySite, _ side: BodySide) -> Double? {
        let raw = entries[key(site, side)] ?? ""
        // A comma decimal separator is what half the world's keyboards produce.
        guard let parsed = Double(raw.replacingOccurrences(of: ",", with: ".")),
              parsed > 0 else { return nil }
        return parsed
    }

    /// The same number in the unit `BodyMeasurement` is defined in.
    ///
    /// The single conversion point. `tapeUnit` supplies both the label the
    /// reader sees and the arithmetic used here, from one `DisplayUnit`, so the
    /// two cannot drift apart.
    private func centimetres(_ site: BodySite, _ side: BodySide) -> Double? {
        typed(site, side).map(tapeUnit.toCanonical)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Measured", selection: $date,
                               in: ...Date(), displayedComponents: .date)
                    Picker("Wearing", selection: $clothing) {
                        ForEach([ScanConditions.Clothing.minimal, .formFitting,
                                 .looseFitting], id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                } footer: {
                    Text("What you're wearing changes the numbers more than anything else does. Recording it is what lets the app tell a real change from a different pair of trousers.")
                }

                scanSection

                Section {
                    MeasurementUnitToggle(quantity: .tapeLength,
                                          preference: $unitPreference)
                } header: {
                    Text("Your tape")
                } footer: {
                    Text("Whichever side of the tape you're reading. Everything below is entered — and converted — in this unit; the app stores centimetres either way, so switching later never changes a measurement you already saved.")
                }

                Section {
                    field(.waist)
                } header: {
                    Text("Waist")
                } footer: {
                    Text("The one that counts. Measured at your natural waist — the narrowest part, usually just above the navel. It's what lets this card judge where your weight sits instead of guessing from BMI.")
                }

                Section {
                    ForEach(Self.order.dropFirst(), id: \.self) { site in
                        field(site)
                    }
                } header: {
                    Text("The rest, if you have them")
                } footer: {
                    Text("All optional. Anything you leave blank is simply not recorded — it isn't stored as zero, and a later measurement fills it in.")
                }
            }
            .navigationTitle("Body measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(measured.isEmpty)
                }
            }
        }
    }

    /// The camera route, offered from inside the tape sheet.
    ///
    /// **Always visible, never hidden for want of hardware.** The row is here on
    /// a phone with no LiDAR, no camera permission and no ARKit at all — it just
    /// says which of those it is, in one line, and the screen behind it explains
    /// properly. Hiding it would make "this phone can't" indistinguishable from
    /// "this app never built it", which is the confusion `InputKind` exists to
    /// end and the reason the 2026-08-07 rule says a card shows even with
    /// nothing behind it.
    ///
    /// The tape stays first among equals in the copy, and that is not modesty:
    /// `BodyMeasurementProvenance.tape` outranks both scan modes, so a reader
    /// with a tape in the drawer should use it.
    @ViewBuilder private var scanSection: some View {
        let availability = BodyScanCaptureAvailability.decide(
            capability: BodyScanCapture.currentCapability,
            authorization: CameraPermission.current,
            policy: model.bodyScanPolicy)

        Section {
            NavigationLink {
                BodyScanCaptureView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan with the camera")
                        Text(scanRowDetail(availability))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "figure.stand")
                }
            }
        } footer: {
            Text("A scan is quicker and a tape is more accurate — the app ranks a tape above both scan modes and never lets a scan overwrite one. Nothing is uploaded either way.")
        }
    }

    private func scanRowDetail(_ availability: BodyScanCaptureAvailability) -> String {
        switch availability {
        case .ready(.lidarDepth), .needsPermission(.lidarDepth):
            return "This phone has a depth sensor, so it can measure rather than infer. Four quarter turns, about a minute."
        case .ready, .needsPermission:
            return "No depth sensor on this phone, so the scan works from your outline — less precise, and the app records which kind each scan was."
        case let .unavailable(block):
            return block.title + " — tap to see why."
        }
    }

    @ViewBuilder private func field(_ site: BodySite) -> some View {
        let bothSides = site.isPaired && showsSides.contains(site)
        VStack(alignment: .leading, spacing: 4) {
            if bothSides {
                row(site, .left, label: "\(site.displayName) (left)")
                row(site, .right, label: "\(site.displayName) (right)")
            } else {
                row(site, .centre, label: site.displayName)
            }
            if site.isPaired {
                Toggle("Measure both sides", isOn: sideToggle(site))
                    .font(.caption)
                    .tint(Theme.accent)
            }
        }
    }

    private func row(_ site: BodySite, _ side: BodySide, label: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(tapeUnit.abbreviation, text: binding(site, side))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(tapeUnit.abbreviation).foregroundStyle(.secondary)
        }
    }

    private func binding(_ site: BodySite, _ side: BodySide) -> Binding<String> {
        Binding(get: { entries[key(site, side)] ?? "" },
                set: { entries[key(site, side)] = $0 })
    }

    private func sideToggle(_ site: BodySite) -> Binding<Bool> {
        Binding(get: { showsSides.contains(site) },
                set: { on in
                    if on { showsSides.insert(site) } else { showsSides.remove(site) }
                })
    }

    private func save() {
        let scan = BodyScan(
            id: UUID(), capturedAt: date, mode: .tape,
            parserVersion: BodyScanParserVersion.current,
            measurements: BodyMeasurements(measured),
            conditions: ScanConditions(clothing: clothing,
                                       hourOfDay: Calendar.current.component(.hour, from: date)),
            // A tape has no raw data to keep, so nothing is retained and
            // `isReparseable` correctly reports false.
            retainedAssets: [])
        model.saveBodyScan(scan)
        dismiss()
    }
}

/// The parser version stamped on every scan.
///
/// Bumped whenever the derivation changes, so `bodyScansAwaitingReparse` can
/// find the scans a newer build could improve. Lives in the app target because
/// the derivation it versions does.
enum BodyScanParserVersion {
    static let current = 1
}
