import SwiftUI
import InsightKit

/// Fast, private, non-judgemental logging of substances. Tapping a chip asks
/// when, pre-filled with now; recent entries can be re-timed or removed.
/// Everything stays on-device.
struct SubstanceLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var justLogged: SubstanceClass?
    /// A substance chosen and awaiting its time.
    @State private var pendingSubstance: SubstanceClass?
    /// An existing entry being re-timed.
    @State private var editing: SubstanceEvent?
    @State private var pendingTime = Date()

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Log a substance").font(.headline)
                            Text("Tap to log it now. This is private, on-device, and just so the app can show how your body responds — no judgement.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(SubstanceClass.allCases) { substance in
                            Button {
                                // Every tap asks when, pre-filled with now, so
                                // confirming is one more tap and correcting is
                                // the same gesture rather than a different one.
                                // This used to log immediately and hide the
                                // picker behind a long-press — an interaction
                                // nobody discovers, which left re-timing as the
                                // only way to fix a time, after the fact.
                                pendingSubstance = substance
                                pendingTime = Date()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: icon(for: substance)).font(.title3)
                                    Text(substance.displayName).font(.caption).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(justLogged == substance ? Theme.accent.opacity(0.18) : Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(justLogged == substance ? Theme.accent : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Tap one and confirm the time — it starts at now, so logging something you had this morning is the same two taps.")
                        .font(.caption2).foregroundStyle(.tertiary).padding(.leading, 4)

                    // Sliced once rather than inside the loop: the old version
                    // re-took `prefix(15)` per row just to find the last id.
                    let recent = Array(model.substanceEvents.prefix(15))
                    if !recent.isEmpty {
                        Text("Recent").font(.subheadline.weight(.semibold)).padding(.leading, 4)
                        Card {
                            VStack(spacing: 0) {
                                ForEach(recent) { event in
                                    row(for: event)
                                    if event.id != recent.last?.id { Divider() }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $pendingSubstance) { substance in
                timeSheet(title: "When was the \(substance.displayName.lowercased())?") {
                    model.logSubstance(substance, at: pendingTime)
                    justLogged = substance
                }
            }
            .sheet(item: $editing) { event in
                timeSheet(title: "When was the \(event.substance.displayName.lowercased())?") {
                    model.updateSubstanceEvent(id: event.id, timestamp: pendingTime)
                }
            }
        }
    }

    /// One logged entry, with its two actions.
    ///
    /// "Edit" is a bordered button with a word in it rather than the bare
    /// caption-sized pencil it replaces. That pencil sat inside a `.caption`
    /// run of secondary text, which put its tap target under the 44pt minimum
    /// and gave it no visual claim to being a control at all — it read as
    /// decoration on the timestamp.
    @ViewBuilder
    private func row(for event: SubstanceEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: event.substance)).frame(width: 24)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.substance.displayName)
                Text(event.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button {
                editing = event
                pendingTime = event.timestamp
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.caption.weight(.medium))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            Button(role: .destructive) {
                model.deleteSubstanceEvent(id: event.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            // The delete target was the glyph's own bounds, which is smaller
            // than a fingertip.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .padding(.vertical, 4)
    }

    /// Date and time only.
    ///
    /// Deliberately no amount. `SubstanceEvent` carries a `units` field and the
    /// analysis has never read it — recording how much would make this a dosing
    /// record, and these features are descriptive harm-reduction, never
    /// encouragement or guidance about quantity.
    @ViewBuilder
    private func timeSheet(title: String, onSave: @escaping () -> Void) -> some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $pendingTime,
                               in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    Text("The before/after comparison lines this up against the hours that followed, so the time matters more than the day.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { pendingSubstance = nil; editing = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        pendingSubstance = nil
                        editing = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func icon(for s: SubstanceClass) -> String {
        switch s {
        case .alcohol: return "wineglass"
        case .caffeine: return "cup.and.saucer"
        case .nicotine: return "smoke"
        case .cannabis: return "leaf"
        case .stimulant: return "bolt"
        case .mdma: return "sparkles"
        case .psychedelic: return "swirl.circle.righthalf.filled"
        case .dissociative: return "moon.zzz"
        case .depressant: return "pills"
        case .other: return "questionmark.circle"
        }
    }
}
