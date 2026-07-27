import SwiftUI
import InsightKit

/// Fast, private, non-judgemental logging of substances. Tapping a chip logs it
/// "now"; recent entries can be edited/removed. Everything stays on-device.
struct SubstanceLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var justLogged: SubstanceClass?

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
                        }
                    }

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
                                        Text(event.timestamp.formatted(.relative(presentation: .named)))
                                            .font(.caption).foregroundStyle(.secondary)
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
        }
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
