import SwiftUI
import InsightKit

/// The Insights tab: analysis-derived, longer-horizon cards (heart-attack risk,
/// heart health, blood pressure, body composition, …) — the things that need
/// trends, not just today's numbers.
///
/// ## The shape of the screen
///
/// Four sections, in this order, each with one job:
///
/// 1. **`suggestionsDrawer`** — "Improve your health", pinned and collapsed. The
///    only thing here about what to *do*, and the reason the tab gets opened.
/// 2. **`heroSection`** — `ScoreBalanceWeb`: every scored insight at once, and
///    the tab's index as well as its summary, since a spoke opens its card.
/// 3. **`cardFeed`** — every trend card, unchanged and in full.
/// 4. **`InstrumentIndexCard`** — the appendix, collapsed: every signal the
///    reader's devices disagree about, and which one the cards above believed.
///    Backlog B3-23. It indexes what it sits under, so it goes last — and being
///    last in the lazy stack is also what keeps its per-metric scan off the
///    path of opening the tab.
///
/// ## What made this tab slow, and what fixed it
///
/// The hero used to be `ScoreComparisonChart`, and building its series called
/// `AppModel.scoreHistory(for:)` for every scored insight **from inside a view
/// body**. Each of those is a 90-day replay that walks the sample set once per
/// replayed day; `AppModel.maxConcurrentReplays` records the four-to-six second
/// scroll freezes that came of starting nine of them on tab open. The card also
/// needed two of them finished before it would draw at all, so the hero was
/// blank for seconds and then shoved the feed downward when it filled.
///
/// The web reads `InsightResult.score` — already computed by `recompute()` — and
/// the cached `ScoreChange`, which comes from *stored* score rows rather than a
/// replay. **Opening this tab now starts no replays.** The comparison chart is
/// unchanged and one tap away in `ScoreComparisonDetailView`, where its replays
/// cost only the reader who asked for it.
struct InsightsListView: View {
    @Environment(AppModel.self) private var model
    /// Collapsed by default. The section is pinned to the top as a persistent
    /// reminder, and a reminder that fills the screen every time you open the
    /// tab stops being one — so it opens as a one-line count and expands on tap.
    @AppStorage("suggestionsExpanded") private var isExpanded = false
    @State private var hero = InsightsHeroModel()
    /// Set by tapping a spoke on the web. See `heroSection` for why the vertices
    /// are not `NavigationLink`s themselves.
    @State private var selectedInsight: InsightID?
    /// The `+`, same one Today and Data carry. This tab shows what the app
    /// makes of your data and had no way to give it any.
    @State private var activeInput: InputKind?

    private var trendResults: [InsightResult] {
        model.results.filter { $0.id.cadence == .trend && $0.isWorthShowing }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.spacing) {
                    suggestionsDrawer
                    heroSection
                    cardFeed
                    // 4. The appendix: where the reader's own devices disagree,
                    // and which one each card believed. Backlog B3-23.
                    //
                    // **Last on purpose, twice over.** It is an index rather
                    // than a headline, so it belongs after the cards it indexes;
                    // and this tab has been made slow twice by work started from
                    // a view body, so being the final child of the `LazyVStack`
                    // means its per-metric scan does not run until somebody
                    // scrolls to it.
                    InstrumentIndexCard()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
            .addInputToolbar($activeInput)
            // On the `ScrollView`, not on the hero card inside the `LazyVStack`:
            // a lazy stack discards the views it has scrolled past, and a
            // destination registered on one of them goes with it — so tapping a
            // spoke after scrolling back up would do nothing.
            .navigationDestination(item: $selectedInsight) { id in
                InsightDetailView(insightID: id)
            }
            .refreshable { await model.refresh() }
            // A dismissal whose suggestion has stopped being made is dead, and
            // this is where it gets cleared — the one screen guaranteed to have
            // forced the (lazy) suggestion list.
            .task { model.pruneResolvedSuggestions() }
            // Kicks the first build, and re-kicks it whenever a refresh lands.
            // `refresh(results:changes:)` is idempotent for unchanged inputs, so
            // calling it from both places costs nothing.
            .task { hero.refresh(results: model.results, changes: scoreChanges) }
            .onChange(of: model.results) {
                hero.refresh(results: model.results, changes: scoreChanges)
            }
        }
    }

    /// Every card's measured movement, keyed by insight.
    ///
    /// `AppModel.scoreChange(for:)` builds its whole cache on the first call and
    /// reads *stored* score rows, so this is one pass over what is already on
    /// disk — not a replay. The cards in the feed below each ask for their own
    /// anyway, so the cache is warm either way.
    private var scoreChanges: [InsightID: ScoreChange] {
        var out: [InsightID: ScoreChange] = [:]
        for result in model.results {
            if let change = model.scoreChange(for: result.id) { out[result.id] = change }
        }
        return out
    }

    // MARK: - 1. Suggestions

    /// "Improve Your Health" — pinned, collapsed, and keeping what you dismissed.
    ///
    /// It lives here rather than only on Today because this is where the
    /// evidence comes from — the busier-versus-lighter-weeks contrast, the
    /// grounding gaps, the signals off baseline are all derived rather than
    /// sensed. Today shows the single best-founded one and lets you wave it
    /// away; this is the list that keeps it, which is what makes dismissing
    /// something on Today safe rather than destructive.
    ///
    /// Dismissed rows stay, dimmed, with a Restore button. A suggestion the
    /// engine has stopped making is gone from both screens without either of
    /// them deciding anything — see `SuggestionVisibility`.
    ///
    /// Silent when there is nothing to say, which is often and correctly so.
    @ViewBuilder private var suggestionsDrawer: some View {
        let rows = model.suggestionVisibility.insights
        if !rows.isEmpty {
            let active = rows.filter { !$0.isDismissed }.count
            Card {
                VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
                    Button {
                        withAnimation(.snappy) { isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.forward.circle")
                            Text("Improve your health").font(.headline)
                            Spacer(minLength: 4)
                            Text(active > 0 ? "\(active)" : "all set")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(active > 0 ? Theme.accent.opacity(0.15)
                                                       : Color.secondary.opacity(0.12),
                                            in: Capsule())
                                .foregroundStyle(active > 0 ? Theme.accent : .secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        Text("What your own data points at, strongest evidence first.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(rows) { row in
                            suggestionRow(row.suggestion, isDismissed: row.isDismissed)
                        }
                        Text("Observations from your own history, not medical advice. Talk to a clinician about anything that concerns you.")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private func suggestionRow(_ suggestion: Suggestion,
                                            isDismissed: Bool) -> some View {
        let row = VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(colour(for: suggestion.basis)).frame(width: 7, height: 7)
                Text(suggestion.title).font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Text(suggestion.detail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Dimmed rather than removed: this list is the reminder, and something
        // you waved away on Today is exactly what it is here to keep hold of.
        .opacity(isDismissed ? 0.45 : 1)

        VStack(alignment: .leading, spacing: 6) {
            if let insight = suggestion.insight {
                NavigationLink { InsightDetailView(insightID: insight) } label: { row }
                    .buttonStyle(.plain)
            } else {
                row
            }
            HStack(spacing: 8) {
                if isDismissed {
                    Button("Show on Today again") {
                        model.restoreSuggestion(id: suggestion.id)
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                } else {
                    Button {
                        model.dismissSuggestion(id: suggestion.id)
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                    .tint(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Green where the evidence is the user's own history, amber where the app is
    /// missing a fact, red where a signal has moved. The dot is a claim about how
    /// well-founded the line is, not about how urgent it is.
    private func colour(for basis: Suggestion.Basis) -> Color {
        switch basis {
        // Several signals agreeing is the best-founded thing this app says, so
        // it takes the same green as an observation from the user's own history
        // rather than a louder hue. The dot ranks evidence; the row's position
        // at the top of the list is what says this one is time-critical.
        case .convergingSignals: return Theme.good
        case .yourOwnData: return Theme.good
        case .unlockAnInsight: return Theme.warn
        case .signalOffBaseline: return Theme.accent
        }
    }

    // MARK: - 2. Hero

    /// The balance web, its one honest sentence, and the way through to the
    /// chart it replaced.
    ///
    /// The card renders in all three states — building, drawable, and too few
    /// scores to enclose a shape — rather than vanishing in two of them. A
    /// section that disappears is an absence the reader cannot read, which is
    /// the rule `SectionPlaceholder` exists to hold on the detail screens.
    ///
    /// A spoke sets `selectedInsight` rather than being a `NavigationLink`
    /// itself: nine links layered inside one card make the whole thing an
    /// ambiguous tap target, and the vertices already carry 44pt hit areas.
    @ViewBuilder private var heroSection: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("How your scores compare").font(.headline)
                    Spacer(minLength: 8)
                    NavigationLink {
                        ScoreComparisonDetailView()
                    } label: {
                        HStack(spacing: 2) {
                            Text("Over time")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.medium))
                    }
                }

                switch hero.phase {
                case .building:
                    ScoreBalanceWebSkeleton()
                        .frame(height: 300)
                        .transition(.opacity)
                case let .ready(snapshot) where snapshot.isDrawable:
                    ScoreBalanceWeb(snapshot: snapshot) { id in
                        selectedInsight = id
                    }
                    .frame(height: 300)
                    .transition(.opacity)
                    if let summary = snapshot.summary {
                        Text(summary)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    legend(for: snapshot)
                case .ready:
                    tooFewScores
                }
            }
        }
    }

    /// Distance from the centre is the score; the outline is what each card is
    /// being judged against. Both need saying — an unexplained second outline
    /// reads as a rendering fault.
    @ViewBuilder private func legend(for snapshot: BalanceWebSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.accent.opacity(0.85))
                        .frame(width: 14, height: 2)
                    Text("Now").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 14, height: 2)
                    Text(snapshot.hasCompleteReference ? "Usual" : "Usual, where measured")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            // **"Usual" on its own is a word, not a definition.** The reader
            // asked what it was averaging over, and the answer is not one
            // window — a daily card is judged against the trailing week and a
            // trend card against the quarter, so the grey shape is a composite.
            // `BalanceWebSnapshot.referenceDescription` says which, from the
            // same `ScoreChange` the vertices came from, so the sentence cannot
            // drift away from the drawing.
            if let described = snapshot.referenceDescription {
                Text(described)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Three spokes is the floor: two scores draw a line segment, which reads as
    /// a chart with a bug in it rather than as a shape.
    private var tooFewScores: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not enough scores to compare yet")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Three cards need to be scoring before their balance can be drawn. Connect a source or add the details a card is asking for, and it will appear here.")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 3. The card feed

    /// Every trend card, unchanged.
    ///
    /// Still one column of full-width `InsightCard`s rather than a grid: each
    /// carries a dial, a headline, a change chip and a driver line, and half a
    /// screen's width truncates the driver line — which is the sentence that
    /// says *why*, and the reason anyone opens the card.
    @ViewBuilder private var cardFeed: some View {
        if !trendResults.isEmpty {
            HStack {
                Text("Deeper analysis of your trends over time.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)

            ForEach(trendResults, id: \.id) { result in
                NavigationLink {
                    InsightDetailView(insightID: result.id)
                } label: {
                    InsightCard(result: result)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
