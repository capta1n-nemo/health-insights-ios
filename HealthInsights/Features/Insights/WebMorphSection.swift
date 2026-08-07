import SwiftUI
import InsightKit

/// Builds the morph timeline off the view body.
///
/// The same shape as `InsightsHeroModel` and for the same reason: this screen
/// has already been the slow one once. The work here is genuinely small — bucket
/// a few thousand `ScorePoint`s and average them — so it runs synchronously
/// rather than detached, and that is a measured choice rather than a hopeful
/// one: **the expensive thing on this screen is the replays**, which have
/// already happened by the time a history arrives here. What matters is that it
/// is not in a `View.body`, where the replays were being triggered from.
///
/// The fingerprint is what makes it safe to call from `.task` and from three
/// `onChange`s: a re-render that changed nothing rebuilds nothing.
@MainActor
@Observable
final class WebMorphModel {

    private(set) var timeline: BalanceWebTimeline = .empty(.month)
    /// Whether a 90-day replay is still running for a card that has no history
    /// yet. Empty and *working* are different states, and the section has to say
    /// which one it is in — the same distinction `SectionPlaceholder.isLoading`
    /// exists for.
    private(set) var isReplaying = false

    @ObservationIgnored private var lastFingerprint: Int?

    func refresh(histories: [InsightID: [ScorePoint]],
                 titles: [InsightID: String],
                 granularity: WebTimeGranularity,
                 isReplaying: Bool) {
        // Outside the fingerprint guard: the histories can be unchanged while a
        // replay starts or finishes, and that flips what the empty state says.
        self.isReplaying = isReplaying

        let fingerprint = Self.fingerprint(histories: histories, granularity: granularity)
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        timeline = BalanceWebTimeline.build(histories: histories, titles: titles,
                                            granularity: granularity)
    }

    /// Identity, extent and endpoints — the three things that change what the
    /// frames are. Not the scores themselves: a replay lands a whole history at
    /// once, so its arrival always moves the count.
    private static func fingerprint(histories: [InsightID: [ScorePoint]],
                                    granularity: WebTimeGranularity) -> Int {
        var hasher = Hasher()
        hasher.combine(granularity)
        for id in histories.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            let points = histories[id] ?? []
            hasher.combine(id)
            hasher.combine(points.count)
            hasher.combine(points.first?.date)
            hasher.combine(points.last?.date)
        }
        return hasher.finalize()
    }
}

/// **The morph slider — backlog P20, the reader's ask.** Walk the balance web
/// back through your own history, one step at a time, with the step width in
/// your hands.
///
/// ## What is drawn, and what is deliberately not
///
/// - **The coloured shape is the step under the slider.** Every position is a
///   real bucket of real scored days — nothing between two positions is drawn,
///   because a shape interpolated between two frames is a web the reader never
///   had. The app's standing rule is that modelled is never dressed as
///   measured, and an in-between polygon has no honest caption.
/// - **The grey hatch is where you are now**, held still while the coloured
///   shape moves, so every frame reads as *then, against today*. It is the same
///   mark the hero uses for "usual" and it means the same kind of thing — the
///   thing being compared against — which is why the legend names it rather
///   than trusting the reader to carry a meaning across two screens.
/// - **Only cards with a score in every step are drawn.** `BalanceWebTimeline`
///   owns that rule and this section prints its consequences: which cards were
///   left out, and that a coarser step usually brings them back. A spoke that
///   appeared and disappeared as the slider moved would rotate the whole chart
///   under the reader's finger.
/// - **The span is on screen, always.** "Life-wide" is not a claim this section
///   is allowed to make loosely: the span grows as replays land and as the app
///   accumulates stored score rows, so the dates are printed from the data every
///   time rather than described in a fixed sentence.
///
/// ## Why it does not open on "now"
///
/// The newest frame *is* the grey underlay, so opening there draws the two
/// shapes on top of one another — a correct picture of nothing. It opens on the
/// oldest step instead, where the contrast the section exists to show is already
/// visible before the reader has touched anything.
struct WebMorphSection: View {
    let timeline: BalanceWebTimeline
    let isReplaying: Bool
    @Binding var granularity: WebTimeGranularity

    /// Which step is drawn. `Double` because `Slider` wants one; snapped to
    /// whole steps, so it can only ever land on a real bucket.
    @State private var step: Double = 0
    /// The spoke the reader last tapped, for the readout under the web. The web
    /// on the Insights tab pushes a card from a vertex; this one must not — a
    /// second `navigationDestination` for `InsightID` inside the same stack
    /// fights the one `InsightsListView` registered, and the useful answer here
    /// is the number at this step against the number now, which is on screen in
    /// one line rather than one push away.
    @State private var selected: InsightID?

    private var frames: [BalanceWebTimeline.Frame] { timeline.frames }

    private var frame: BalanceWebTimeline.Frame? {
        guard !frames.isEmpty else { return nil }
        let index = min(max(Int(step.rounded()), 0), frames.count - 1)
        return frames[index]
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header
                granularityPicker

                if let frame, timeline.isMorphable {
                    ScoreBalanceWeb(snapshot: frame.snapshot) { id in
                        selected = (selected == id) ? nil : id
                    }
                    .frame(height: 300)
                    readout(frame)
                    slider
                    caption(frame)
                    legend
                    coverageNote
                } else {
                    emptyState
                }

                spanNote
            }
        }
        // The frames are rebuilt when a replay lands or the step width changes,
        // and the slider's position means nothing across a rebuild — 40 weeks
        // is not 40 months. Land on the oldest step, which is where this opens.
        .onChange(of: frames.count) { step = 0 }
        .onChange(of: granularity) { step = 0 }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How your balance has moved").font(.headline)
            Text("Walk the web back through your own history. Each step is a real \(timeline.granularity.stepNoun) of scored days — nothing is drawn between two of them.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The step width. It is not a display preference — it decides which cards
    /// clear the coverage rule, which is why the sentence under the empty state
    /// points back at it.
    private var granularityPicker: some View {
        Picker("Step", selection: $granularity) {
            ForEach(WebTimeGranularity.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    private var slider: some View {
        VStack(spacing: 2) {
            Slider(value: $step,
                   in: 0...Double(max(frames.count - 1, 1)),
                   step: 1) {
                Text("Step through your history")
            } minimumValueLabel: {
                Text("Earliest").font(.caption2).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text("Now").font(.caption2).foregroundStyle(.tertiary)
            }
            .tint(Theme.accent)
        }
    }

    /// Which step is drawn, and how much is behind it.
    ///
    /// The day count is not decoration: a frame built from two scored days is a
    /// thinner claim than one built from ninety, and at weekly steps the two sit
    /// one slider position apart.
    private func caption(_ frame: BalanceWebTimeline.Frame) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label(for: frame)).font(.subheadline.weight(.medium))
            Text("\(frame.scoredDayCount) scored \(frame.scoredDayCount == 1 ? "day" : "days") across \(timeline.spokeCount) cards")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    /// One line for the tapped spoke: this step against now.
    @ViewBuilder private func readout(_ frame: BalanceWebTimeline.Frame) -> some View {
        if let selected, let spoke = frame.snapshot.spokes.first(where: { $0.id == selected }) {
            let then = Int(spoke.score.rounded())
            HStack(spacing: 6) {
                Circle().fill(Theme.color(forScore: spoke.score)).frame(width: 7, height: 7)
                Text(spoke.shortTitle).font(.caption.weight(.medium))
                if let reference = spoke.reference {
                    Text("\(then) then · \(Int(reference.rounded())) now")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text("\(then) then").font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        } else {
            Text("Tap a point to read it against today.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.accent.opacity(0.85))
                    .frame(width: 14, height: 2)
                Text("This \(timeline.granularity.stepNoun)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 14, height: 2)
                Text("Where you are now").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// What was left out, and the one control that changes it.
    @ViewBuilder private var coverageNote: some View {
        if !timeline.excluded.isEmpty {
            Text("\(list(timeline.excluded)) \(timeline.excluded.count == 1 ? "is" : "are") not drawn — each is missing a score in at least one \(timeline.granularity.stepNoun), and a shape can only be read against the shape beside it if every card on it has a real value. A coarser step usually brings them back.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// **The span, printed from the data.** A chart that silently changes the
    /// stretch of life it covers is exactly the ambiguity this app exists to
    /// avoid, and this one's span moves whenever a replay lands or another day
    /// is stored.
    @ViewBuilder private var spanNote: some View {
        if let span = timeline.span, let days = timeline.dayCount {
            Text("Drawn from your full recorded history: \(span.lowerBound.formatted(date: .abbreviated, time: .omitted)) to \(span.upperBound.formatted(date: .abbreviated, time: .omitted)) — \(days) \(days == 1 ? "day" : "days"), \(frames.count) \(frames.count == 1 ? timeline.granularity.stepNoun : timeline.granularity.stepNoun + "s"). It grows as the app records more.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Nothing to morph yet

    /// Always rendered, and it says what it is waiting for.
    ///
    /// Four different silences, and only one of them is "come back later":
    /// working, one step, too few cards clearing coverage, and no scored history
    /// at all. Announcing the wrong one is how a section that fixes itself in a
    /// second reads as a section that never will.
    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isReplaying && frames.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Replaying your score history…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Your scores are being rebuilt from your raw samples. This runs once.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if frames.isEmpty && timeline.excluded.isEmpty {
                Text("No scored history yet").font(.subheadline).foregroundStyle(.secondary)
                Text("Nothing has been scored often enough to walk backwards through. Cards start recording a score the day they can produce one.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if frames.isEmpty {
                Text("No card covers every \(timeline.granularity.stepNoun) yet")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("\(list(timeline.excluded)) each miss at least one \(timeline.granularity.stepNoun) of your history. A coarser step is the fix — try \(coarserSuggestion).")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if frames.count < 2 {
                Text("Only one \(timeline.granularity.stepNoun) so far")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("There is nothing to morph between until your history covers two. A finer step would split what you already have — try \(finerSuggestion).")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not enough cards to draw a shape")
                    .font(.subheadline).foregroundStyle(.secondary)
                // The floor is read from the geometry rather than written out,
                // so this sentence cannot outlive the rule it quotes — backlog
                // D19, where a section said "All four" on a card running on
                // three signals.
                Text("\(BalanceWebGeometry.minimumSpokes) cards need a score in every \(timeline.granularity.stepNoun) before their balance can be enclosed. Fewer than that draws a line rather than a shape, which reads as a fault.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }

    private var coarserSuggestion: String {
        switch granularity {
        case .week: return "monthly"
        case .month, .quarter: return "quarterly"
        }
    }

    private var finerSuggestion: String {
        switch granularity {
        case .quarter: return "monthly"
        case .month, .week: return "weekly"
        }
    }

    // MARK: - Words

    /// The step's own name. Quarters get their months spelled out rather than
    /// "Q2" — the reader has never been shown a quarter label anywhere else in
    /// this app, so the abbreviation would need a legend of its own.
    private func label(for frame: BalanceWebTimeline.Frame) -> String {
        switch timeline.granularity {
        case .week:
            return "Week of \(frame.start.formatted(date: .abbreviated, time: .omitted))"
        case .month:
            return frame.start.formatted(.dateTime.month(.wide).year())
        case .quarter:
            let last = frame.end.addingTimeInterval(-86_400)
            return "\(frame.start.formatted(.dateTime.month(.abbreviated)))–\(last.formatted(.dateTime.month(.abbreviated).year()))"
        }
    }

    /// "Sleep", "Sleep and Food", "Sleep, Food and Walking" — and never a bare
    /// comma-joined list, which reads as a debug dump in a sentence.
    private func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }
}
