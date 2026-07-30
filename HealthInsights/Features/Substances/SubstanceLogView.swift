import SwiftUI
import InsightKit

/// Fast, private, non-judgemental logging of substances. Tapping a chip logs it
/// "now"; recent entries can be edited/removed. Everything stays on-device.
struct SubstanceLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var justLogged: SubstanceClass?
    /// A substance chosen by long-press, awaiting a time.
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
                                // A tap still logs "now" — the whole point of the
                                // grid is that logging is one gesture. Long-press
                                // opens the picker for something that happened
                                // earlier, which is the common correction and had
                                // no path at all before.
                                model.logSubstance(substance)
                                justLogged = substance
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
                            .simultaneousGesture(LongPressGesture().onEnded { _ in
                                pendingSubstance = substance
                                pendingTime = Date()
                            })
                        }
                    }
                    Text("Tap to log it now, or press and hold to set a time.")
                        .font(.caption2).foregroundStyle(.tertiary).padding(.leading, 4)

                    if !model.substanceEvents.isEmpty {
                        Text("Recent").font(.subheadline.weight(.semibold)).padding(.leading, 4)
                        Card {
                            VStack(spacing: 0) {
                                ForEach(Array(model.substanceEvents.prefix(15))) { event in
                                    HStack {
                                        Image(systemName: icon(for: event.substance)).frame(width: 24)
                                            .foregroundStyle(Theme.accent)
                                        Text(event.substance.displayName)
                                        Spacer()
                                        // Tappable: a mis-timed entry used to be
                                        // correctable only by deleting it.
                                        Button {
                                            editing = event
                                            pendingTime = event.timestamp
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(event.timestamp.formatted(.relative(presentation: .named)))
                                                Image(systemName: "pencil").font(.caption2)
                                            }
                                            .font(.caption).foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        Button(role: .destructive) {
                                            model.deleteSubstanceEvent(id: event.id)
                                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                            .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 7)
                                    if event.id != model.substanceEvents.prefix(15).last?.id {
                                        Divider()
                                    }
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
