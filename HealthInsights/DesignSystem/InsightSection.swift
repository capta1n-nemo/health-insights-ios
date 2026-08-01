import SwiftUI
import InsightKit

/// Whether a section shows its content straight away, or keeps it behind a
/// one-line preview the reader opens.
///
/// ## Why any section would arrive closed
///
/// "Patterns worth a look" and "What comes first" render on every card now,
/// including the cards where the honest answer is "nothing yet" — which is the
/// point. A section that disappears when it finds nothing teaches the reader
/// that its absence means nothing in particular, when in fact it means one of
/// *no data*, *not enough days*, or *nothing stood out*, and only the last of
/// those is reassuring. See `FindingsPlaceholder`.
///
/// But two more always-on sections in the middle of an already long card are
/// two more things to scroll past on the days they have nothing to say, so they
/// arrive closed with their finding — or their reason — on the outside.
enum SectionExpansion {
    /// Content visible, as every section was before this existed.
    case always
    /// Closed by default. `preview` stands in for the content, so it has to be
    /// worth reading on its own.
    case collapsed(preview: String)
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
    let title: String
    /// An SF Symbol beside the title. Two sections had one and ten did not;
    /// keeping it optional rather than removing it preserves the distinction
    /// those two were drawing (a finding, rather than a record).
    var icon: String?
    /// The one figure. See the rule above.
    var trailing: String?
    let caveat: SectionCaveat
    /// Open, or closed behind a preview. Defaulted, unlike `caveat`: the risk
    /// that a required argument defends against — a section shipping without
    /// saying what it inferred — has no analogue here, and ten of the twelve
    /// sections open.
    var expansion: SectionExpansion = .always
    @ViewBuilder var content: Content

    @State private var isExpanded = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                switch expansion {
                case .always:
                    headerRow(showsChevron: false)
                    content
                    caveatLine
                case .collapsed(let preview):
                    disclosure(preview: preview)
                    // The caveat travels with the content it qualifies. Shown
                    // while closed it would be a footnote about nothing.
                    if isExpanded {
                        content
                        caveatLine
                    }
                }
            }
        }
    }

    /// The closed state is the whole design. A collapsed section showing only
    /// its title is a locked door; one showing its strongest finding — or the
    /// reason there isn't one — has already answered the reader who never opens
    /// it, and tempted the one who might.
    private func disclosure(preview: String) -> some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                headerRow(showsChevron: true)
                if !isExpanded {
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
        .accessibilityHint(isExpanded ? "Double tap to collapse this section"
                                      : "Double tap to expand this section")
    }

    private func headerRow(showsChevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let icon {
                Label(title, systemImage: icon).font(.headline)
            } else {
                Text(title).font(.headline)
            }
            // Without a trailing figure or a chevron there is nothing to push
            // away from the title, and an unconditional spacer would change the
            // ten open sections' layout for no reason.
            if trailing != nil || showsChevron {
                Spacer(minLength: 8)
            }
            if let trailing {
                Text(trailing)
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
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
    let title: String
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
