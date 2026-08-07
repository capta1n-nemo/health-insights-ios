import SwiftUI
import InsightKit

/// **"A source you connected isn't reporting."** Backlog D10.
///
/// ## The walk that produced this
///
/// D10 asked what the reader sees when a connector fails. On 2026-08-07 the
/// token-expiry path was finally walked — see `ConnectorFaultInjection`, which
/// exists because it could not be walked before — and the Today tab looked like
/// this, with three providers connected and all three refused with HTTP 401 in
/// the same second:
///
/// > Readiness — **Connect a wearable**
/// > Symptom radar — **Wear your watch to sleep**
/// > Sleep — **Connect a sleep source**
///
/// Every one of those is an instruction to do something the reader has already
/// done. The app *knew* — three failures in the log, three red rows in Settings,
/// `status` on all three set to `.error` — and the tab they actually look at
/// said the opposite, in the confident voice it uses for a new install.
///
/// This is the same defect `waitingOn` was written for two days earlier (Travel
/// drain saying *"Connect your calendar"* to a reader whose calendar was
/// connected), one level up: there the card could not tell *thin* from *absent*;
/// here the app cannot tell *never connected* from *connected and broken*. It
/// can. It just wasn't saying.
///
/// ## Why a section and not a fix to each card
///
/// A card's empty state answers *"what would make me able to score this"*, and
/// its honest answer really is "a wearable's data" — the card does not know
/// which of six sources was meant to supply it, and inventing that map is the
/// mistake `InstrumentCoverageSection` refuses to make for the same reason.
/// What was missing is one place that owns the *source* fact and sits above the
/// cards, so the reader meets the cause before the symptoms. The last line of
/// this section is therefore load-bearing: it says in plain words that the
/// "connect a…" prompts below are about *this*.
///
/// ## What it will not do
///
/// **It never invents an instruction.** `SyncTrouble.action` is `nil` for a
/// failure the reader cannot act on — no network, a rate limit, a provider
/// having a bad afternoon — and this renders nothing where the button would be.
/// Telling someone to reconnect an account over a train tunnel is worse than
/// silence: they re-authorise a connection that was never broken, and the fresh
/// grant destroys the evidence of what the old one was doing.
///
/// **It does not appear when nothing is wrong.** Rule 7 — every *card* shows,
/// with no data — is about cards; a permanent "all sources fine" banner is
/// status furniture on a tab meant to be a glance, and it would train the
/// reader to skip precisely the strip that matters on the day it changes.
struct ConnectorTroubleSection: View {
    @Environment(AppModel.self) private var model

    /// Sources whose last sync went wrong, in registry order — which is the
    /// order Settings lists them, so the reader can go from one to the other.
    ///
    /// Deliberately keyed off `syncTrouble` and not off `status`, because the
    /// two failures that hurt most *leave the status green*: HealthKit reading
    /// nothing after a refusal, and an OAuth grant that 401s every collection
    /// while the connection itself stays up. A section that only listened for
    /// `.error` would have missed both.
    ///
    /// Read from `AppModel.integrationTroubles` rather than off the providers,
    /// which are `ObservableObject`s that `@Observable` does not track — the
    /// same reason `integrationStatuses` exists. Asking the provider directly
    /// compiles, renders correctly once, and then never updates again.
    private var troubled: [(name: String, icon: String, trouble: SyncTrouble)] {
        model.registry.integrations.compactMap { integration in
            guard let trouble = model.integrationTroubles[integration.id] else { return nil }
            return (integration.displayName, integration.iconSystemName, trouble)
        }
    }

    var body: some View {
        if !troubled.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    ForEach(troubled, id: \.name) { entry in
                        row(entry)
                    }
                    Divider()
                    footer
                }
            }
        }
    }

    private var header: some View {
        // The count comes from the list beside it and is never written out —
        // a sentence stating a size the code owns is how these drift apart.
        Label(troubled.count == 1
              ? "A source you connected isn't reporting"
              : "\(troubled.count) sources you connected aren't reporting",
              systemImage: "exclamationmark.triangle.fill")
            .font(.headline)
            .foregroundStyle(Theme.bad)
    }

    private func row(_ entry: (name: String, icon: String, trouble: SyncTrouble)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.icon)
                .font(.subheadline)
                .frame(width: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.subheadline.weight(.semibold))
                Text(entry.trouble.summary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.trouble.cause)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Nothing at all when there is nothing to do. See the type note
                // on `SyncTrouble.action`.
                if let action = entry.trouble.action {
                    Text(action)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name). \(entry.trouble.summary) \(entry.trouble.cause) "
                            + (entry.trouble.action ?? "There is nothing to do about this."))
    }

    /// The two sentences the walk showed were missing, and they are the reason
    /// this section exists rather than a red dot in Settings.
    ///
    /// The first stops the reader acting on the cards' instructions. The second
    /// is the standing rule this app is built on, restated at the one moment it
    /// could plausibly be doubted: **nothing was estimated to cover the gap.**
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cards below may still say \u{201C}connect a wearable\u{201D} or "
                 + "\u{201C}wear your watch\u{201D}. They mean \u{201C}no recent data\u{201D}, "
                 + "and this is why.")
            Text("Nothing has been estimated to fill the gap. The readings already on this "
                 + "phone are untouched, and will go on ageing until a sync succeeds.")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
