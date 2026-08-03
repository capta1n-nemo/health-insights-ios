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
    /// Centimetres as typed, keyed by site **and side** — a paired site has two
    /// independent fields. Empty means "not measured", which is different from
    /// zero and must stay that way.
    @State private var entries: [String: String] = [:]
    /// Paired sites get a second field when the reader wants both sides.
    @State private var showsSides: Set<BodySite> = []

    /// The order they are asked for: the one that scores, then trunk, then limbs.
    private static let order: [BodySite] = [.waist, .hip, .chest, .neck,
                                            .shoulderWidth, .thigh, .upperArm,
                                            .calf, .forearm, .underbust, .abdomen]

    private var measured: [BodyMeasurement] {
        var out: [BodyMeasurement] = []
        for site in Self.order {
            if site.isPaired, showsSides.contains(site) {
                if let left = value(site, .left) {
                    out.append(.init(site: site, side: .left, centimetres: left))
                }
                if let right = value(site, .right) {
                    out.append(.init(site: site, side: .right, centimetres: right))
                }
            } else if let single = value(site, .centre) {
                out.append(.init(site: site, side: .centre, centimetres: single))
            }
        }
        return out
    }

    private func key(_ site: BodySite, _ side: BodySide) -> String {
        "\(site.rawValue).\(side.rawValue)"
    }

    private func value(_ site: BodySite, _ side: BodySide) -> Double? {
        let raw = entries[key(site, side)] ?? ""
        // A comma decimal separator is what half the world's keyboards produce.
        guard let parsed = Double(raw.replacingOccurrences(of: ",", with: ".")),
              parsed > 0 else { return nil }
        return parsed
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
            TextField("cm", text: binding(site, side))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("cm").foregroundStyle(.secondary)
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
