import SwiftUI
import InsightKit

/// **Every calendar event the app holds, and what it decided each one was.**
///
/// ## Why this exists (backlog D49)
///
/// `docs/data-conventions.md` ▸ rule 2: every domain row opens a read-only
/// detail page. `calendarSection` rendered three bucket counts and opened
/// nothing, behind a `// data-detail: exempt` naming D49 — an exemption written
/// to be spent.
///
/// The events *were* reachable: the review list lives on the Work impact and
/// Travel drain cards. But only two buckets are reachable that way — a personal
/// event, or one the classifier could not place, appears on neither card, so it
/// was counted in the Data tab and visible nowhere. That is not a convention
/// gap, it is data the app holds and never showed.
///
/// ## Read-only, and the correction lives elsewhere on purpose
///
/// The cards' review list is an *editing* surface: every judgement-call chip is
/// a picker, edits accumulate in a view-local draft, and confirming writes a
/// `CalendarEventJudgement`. Reproducing that here would be a second
/// implementation of the correction path — which
/// `InsightDetailView.calendarReviewSection` already refuses to have ("two
/// copies of a review list is two places for the correction path to diverge").
///
/// So this page states what is stored and says plainly where to change it. The
/// same split the whole Data tab makes: reviewing here, adding and correcting
/// in the sheets and cards that own those gestures.
///
/// ## No chart
///
/// There is no shared chart component for calendar events, and rule 3 forbids a
/// data page hand-rolling a raw Swift Charts view. The overview is the bucket
/// breakdown and the accuracy figure instead.
///
/// (Worded that way on purpose: `verify.sh`'s raw-chart lint greps the file
/// text and does not skip comments, so spelling the banned construct out in
/// prose fails the gate. It caught this comment on its first run.)
struct CalendarEventsDataView: View {
    @Environment(AppModel.self) private var model

    /// Every event, newest first, with the bucket it currently falls in.
    ///
    /// From `calendarBuckets` rather than from `calendarReview`, because that
    /// one drops any event with no stored judgement — and an unjudged event is
    /// still an event the app holds, which is exactly what this tab claims to
    /// list. The classifier fills the gap in-flight for those.
    private var rows: [(event: CalendarEvent, bucket: CalendarEventBucket)] {
        let buckets = model.calendarBuckets
        var bucketByID: [String: CalendarEventBucket] = [:]
        for (bucket, events) in buckets {
            for event in events { bucketByID[event.id] = bucket }
        }
        return model.calendarEvents
            .sorted { $0.start > $1.start }
            .map { ($0, bucketByID[$0.id] ?? .other) }
    }

    var body: some View {
        let buckets = model.calendarBuckets
        let accuracy = model.calendarAccuracy
        return DomainDataScaffold(
            title: DataDomain.calendarEvents.title,
            entriesHeader: "Events",
            entryCount: model.calendarEvents.count,
            emptyHeadline: "No events yet",
            emptyMessage: "Once you allow calendar access, your events appear here — sorted into work, personal and travel.",
            emptySymbol: "calendar",
            overview: {
                Section {
                    // Every bucket, including the empty ones: "no travel
                    // events" is an answer, and a bucket that silently
                    // disappears reads as a bucket that does not exist.
                    ForEach(CalendarEventBucket.allCases) { bucket in
                        HStack {
                            Text(bucket.title)
                            Spacer()
                            Text("\(buckets[bucket]?.count ?? 0)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } header: {
                    Text("How they were sorted")
                } footer: {
                    Text(DataDomain.calendarEvents.summary)
                }
                Section {
                    Text(accuracySentence(accuracy))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Where the correcting happens. Named rather than linked:
                    // this page has no route into a card, and a dead-looking
                    // link is worse than a sentence that says where to go.
                    Text("Confirming or correcting one of these happens on the Work impact and Travel drain cards, where the whole review list lives. Nothing on this page changes what is stored.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("How often it is right")
                }
            },
            rows: {
                ForEach(rows, id: \.event.id) { row in
                    eventRow(row.event, bucket: row.bucket)
                }
            })
    }

    /// The accuracy sentence, or an honest statement that there isn't one yet.
    ///
    /// Same refusal as `CycleSummary.lengthRange`: below the threshold there is
    /// no figure, and inventing one from three answers would be worse than
    /// silence.
    private func accuracySentence(_ accuracy: CalendarClassifierAccuracy) -> String {
        if let rate = accuracy.rate {
            return String(format: "You have reviewed %d, and the app was right %.0f%% of the time.",
                          accuracy.reviewed, rate * 100)
        }
        return "\(accuracy.reviewed) reviewed so far. It needs \(CalendarEventClassifier.minimumReviewedForAccuracy) before a percentage means anything."
    }

    private func eventRow(_ event: CalendarEvent, bucket: CalendarEventBucket) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // ⚠️ **No `lineLimit(1)`.** The raw-field rows on this tab
                // learnt that the hard way — a row whose whole subject is its
                // name, with the distinguishing words truncated away.
                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dateLine(event))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Text(bucket.title)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// All-day events say so rather than claiming a time nobody set.
    private func dateLine(_ event: CalendarEvent) -> String {
        event.isAllDay
            ? "\(event.start.formatted(date: .abbreviated, time: .omitted)) · all day"
            : event.start.formatted(date: .abbreviated, time: .shortened)
    }
}
