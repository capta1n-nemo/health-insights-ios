import SwiftUI
import InsightKit

/// How a section arrives — open, or closed behind a one-line preview.
///
/// **Every section can be closed either way.** This says only what it does
/// before the reader has touched it, and that distinction is the whole of this
/// type. It was got wrong once: an earlier version made *collapsed* and
/// *collapsible* the same thing, so "Score over time" could be minimised while
/// it was empty and then lost its chevron the moment the replay landed. The
/// reader could close the section that had nothing in it and not the one that
/// did.
///
/// ## Why a section would arrive closed
///
/// "Patterns worth a look", "What comes first" and "How this is weighted" render
/// on every card, including the cards where the honest answer is "nothing yet" —
/// which is the point. A section that disappears when it finds nothing teaches
/// the reader that its absence means nothing in particular, when in fact it
/// means one of *no data*, *not enough days*, or *nothing stood out*, and only
/// the last is reassuring. See `SectionPlaceholder`.
///
/// But three more always-on sections in the middle of an already long card are
/// three more things to scroll past on the days they have nothing to say, so
/// they arrive closed with their finding — or their reason — on the outside.
struct SectionExpansion {
    /// Whether the section is open before the reader has chosen.
    let startsExpanded: Bool

    /// The line standing in for the content while the section is closed.
    ///
    /// Optional, and nil for a section that arrives open: `trailing` is already
    /// "the one number that makes the section worth opening", and somebody who
    /// closed a section themselves does not need telling what they closed.
    let preview: String?

    /// Open on arrival, and closable. The default, and what most sections want.
    static let open = SectionExpansion(startsExpanded: true, preview: nil)

    /// Closed on arrival. `preview` is required rather than optional here: a
    /// section nobody has opened yet, showing only its title, is a locked door.
    static func collapsed(preview: String) -> SectionExpansion {
        SectionExpansion(startsExpanded: false, preview: preview)
    }
}

/// One section of a card screen: a title, at most one figure, the content, and
/// an honest note about what the content is not.
///
/// ## Why this exists
///
/// `Card` supplies the rounded rectangle and nothing else, so every section on
/// `InsightDetailView` hand-rolled its own header `HStack` and its own footnote.
/// Read across the file, that produced three colours doing one job
/// (`.tertiary`, `.secondary` and `Theme.warn` were all in use as the caveat
/// line), four different header fonts, inner spacings of 8, 10 and 12 chosen at
/// random, and a trailing slot that changed *quantity* under a fallback — the
/// body-composition trend showed a kilogram delta, or a count of weigh-ins, in
/// the same position with nothing to tell them apart.
///
/// ## The two rules, stated once
///
/// **A trailing figure is the one number that makes the section worth opening.**
/// One slot, one quantity — never a different measurement when the first is
/// unavailable. If the figure cannot be produced, the slot is empty.
///
/// **A section that infers rather than reports must say so.** `caveat` has no
/// default, so leaving it out is a compile error and `.none` is a choice
/// somebody made. That is the whole reason this is a required argument rather
/// than a convention: the previous convention was followed by four sections out
/// of twelve, and the one it was skipped on — "What comes first", a lag fitted
/// through a handful of overlapping days — was the most inferential claim on the
/// screen.
///
/// The caveat's words live in `SectionCaveat`, in InsightKit, because the app
/// target has no test target and the wording is the honesty claim.
struct InsightSection<Content: View>: View {
    /// `LocalizedStringResource`, not `String` (D7): a literal at any of the
    /// dozens of call sites is then a localisation key the compiler extracts
    /// into the String Catalog, with no edit at the site. A caller whose title
    /// is genuinely computed at runtime must build the resource itself — which
    /// is the point: dynamic display copy is a decision, not a default.
    let title: LocalizedStringResource
    /// An SF Symbol beside the title. Two sections had one and ten did not;
    /// keeping it optional rather than removing it preserves the distinction
    /// those two were drawing (a finding, rather than a record).
    var icon: String?
    /// The one figure. See the rule above.
    var trailing: String?
    let caveat: SectionCaveat
    /// Whether it arrives open or closed. Defaulted, unlike `caveat`: the risk a
    /// required argument defends against — a section shipping without saying
    /// what it inferred — has no analogue here, and most sections arrive open.
    var expansion: SectionExpansion = .open
    @ViewBuilder var content: Content

    /// What the reader chose, and `nil` until they choose.
    ///
    /// **Not a plain `Bool` seeded from `expansion`.** `startsExpanded` is
    /// derived from data that arrives *after* the first render — "Score over
    /// time" is closed while its replay runs and open once it lands — and a
    /// plain flag would either freeze the section at whichever state it was
    /// born in, or reopen a section the reader had deliberately closed every
    /// time new data appeared. Three states, because there are three: closed by
    /// the reader, opened by the reader, and not yet asked.
    @State private var readerChoice: Bool?

    private var isExpanded: Bool { readerChoice ?? expansion.startsExpanded }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                disclosure
                // The caveat travels with the content it qualifies. Shown while
                // closed it would be a footnote about nothing.
                if isExpanded {
                    content
                    caveatLine
                }
            }
        }
    }

    /// The whole header is the control, on every section.
    ///
    /// The closed state is the design for the sections that arrive closed: one
    /// showing only its title is a locked door, while one showing its strongest
    /// finding — or the reason there isn't one — has already answered the reader
    /// who never opens it, and tempted the one who might.
    private var disclosure: some View {
        Button {
            // From the *effective* state rather than toggling the optional: the
            // first tap on an open-by-default section has to close it, and
            // `readerChoice?.toggle()` on a nil would do nothing at all.
            withAnimation(.snappy) { readerChoice = !isExpanded }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                headerRow
                if !isExpanded, let preview = expansion.preview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // `Text` per branch rather than a bare ternary: two string literals
        // in a ternary infer `String` and take the verbatim overload, so the
        // hint never reached the String Catalog (D7).
        .accessibilityHint(isExpanded ? Text("Double tap to collapse this section")
                                      : Text("Double tap to expand this section"))
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            if let icon {
                Label(String(localized: title), systemImage: icon).font(.headline)
            } else {
                Text(title).font(.headline)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // Full strength only where it is inviting a tap. On a closed
            // section the chevron is the only thing saying there is more
            // behind it; on an open one it is a spare affordance, and eleven
            // of them at full accent down a card reads as a row of alarms.
            //
            // Dimmed rather than recoloured: `foregroundStyle` across a
            // ternary of two different style types needs `AnyShapeStyle`, and
            // `AnyShapeStyle(.tertiary)` cannot infer its base — an inference
            // gamble in a target only CI compiles.
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .opacity(isExpanded ? 0.4 : 1)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
    }

    /// Always `.tertiary`. A caveat is context, not a warning — `Theme.warn` was
    /// in use here for the body-composition case where a scale contradicts
    /// itself, and that is a *finding* about the data, so it belongs in the
    /// content where it can be read as one.
    @ViewBuilder private var caveatLine: some View {
        if let text = caveat.text {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A section that already sits inside another section's `Card`, so it brings the
/// header and the caveat but not a second rounded rectangle.
///
/// Body Composition is the case: "What you're made of" and its history are two
/// pictures of one subject, and the bespoke slot is one slot. Written as its own
/// type rather than a `showsCard` flag, because a flag on a container is the
/// shape that ends up with two call sites passing it for two different reasons.
struct NestedInsightSection<Content: View>: View {
    /// Same reasoning as `InsightSection.title` — see the note there (D7).
    let title: LocalizedStringResource
    var trailing: String?
    let caveat: SectionCaveat
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                if let trailing {
                    Spacer(minLength: 8)
                    Text(trailing)
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            content
            if let text = caveat.text {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
