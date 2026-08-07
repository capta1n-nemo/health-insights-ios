import Foundation

/// "Where are you with this, and what would move it" — for any `ContributionRoute`.
///
/// ## Why the three routes needed one of these
///
/// `ViewAndAddSection`'s own doc comment claims "the anatomy is fixed whatever
/// the route". Read against the code it was not: blood pressure had a grounded
/// summary, substances had none, and the facts route expressed the same idea as
/// a column of green ticks. Each route also previewed its own contents — three
/// readings, three events, every fact with its value — which is what this change
/// removes: the card says *where you are*, and the sub-menu behind the button
/// holds *what you have given*.
///
/// The parts that can be wrong are which state counts as grounded and what the
/// figure says, and those are the parts a view cannot test. Blood pressure is
/// deliberately not re-derived here — it defers to
/// `BloodPressureEstimator.CalibrationStatus`, which already owns the
/// five-then-two rule and its wording. A second opinion on "are you calibrated"
/// is exactly the kind of duplicate this app has been bitten by.
public struct ContributionSummary: Sendable, Equatable {

    /// Whether this route has everything it asks for.
    public let isGrounded: Bool
    /// The one figure in the section header — the thing that makes the section
    /// worth looking at when there is nothing to add.
    public let figure: String
    /// The sentence beside the seal.
    public let guidance: String
    /// Fill for a progress bar, or `nil` when there is nothing left to fill.
    /// A full bar next to a green seal says the same thing twice.
    public let progress: Double?
    /// The words on the button that opens the sub-menu.
    public let addLabel: String
    /// A label for the route's dated history, where one exists beyond the entry
    /// sheet, or `nil` where the entry surface already *is* the full view.
    ///
    /// Blood pressure and medication have one — a readings screen, a dose and
    /// side-effect list — while the substance log and the grounding list are
    /// single screens that already show everything they hold. Informational
    /// since 2026-08-02: viewing moved to the one consolidated `CardDataView`,
    /// so this is no longer rendered as a per-route link, but it remains the
    /// tested statement of *what history a route has* for any surface that needs
    /// to word it.
    public let detailLabel: String?

    // MARK: - Routes

    /// Defers entirely to the calibration status for the grounded question, the
    /// target and the sentence. Only the labels are new.
    public static func bloodPressure(
        _ status: BloodPressureEstimator.CalibrationStatus
    ) -> ContributionSummary {
        ContributionSummary(
            isGrounded: status.isGrounded,
            figure: "\(status.recentReadings) in 30 days",
            guidance: status.guidance,
            progress: status.isGrounded || status.required == 0
                ? nil
                : Swift.min(1, Double(status.recentReadings) / Double(status.required)),
            addLabel: "Add a reading",
            detailLabel: status.totalReadings > 0
                ? "All \(status.totalReadings) \(SectionCaveat.plural(status.totalReadings, "reading")) and calibration detail"
                : "Readings and calibration detail")
    }

    /// A log has no target, so "grounded" here means only that there is
    /// something to compare against. Deliberately not a count threshold: the
    /// model decides for itself whether it has enough to say anything, and a
    /// second bar here would be this view inventing a requirement.
    public static func substances(logged: Int) -> ContributionSummary {
        ContributionSummary(
            isGrounded: logged > 0,
            figure: logged == 0 ? "None yet" : "\(logged) logged",
            guidance: logged == 0
                ? "Nothing logged yet. Logging what you have — and when — is what "
                    + "lets the app compare the hours afterwards against your ordinary days."
                : "\(logged) \(SectionCaveat.plural(logged, "entry", plural: "entries")) "
                    + "recorded. Private and on-device, so the app can show how your "
                    + "body responds — no judgement, and no amounts.",
            progress: nil,
            addLabel: logged == 0 ? "Log something" : "View & add entries",
            detailLabel: nil)
    }

    /// A GLP-1 regimen, its doses and the side effects logged against it.
    ///
    /// "Grounded" is having a regimen at all, not a dose count: the app can draw
    /// the curve and read the weight trend from the first dose onward, and
    /// setting a target number of injections would be this view inventing a
    /// clinical opinion.
    public static func medication(hasRegimen: Bool, doses: Int,
                                  sideEffects: Int) -> ContributionSummary {
        guard hasRegimen else {
            return ContributionSummary(
                isGrounded: false,
                figure: "Not set up",
                guidance: "If you're taking a GLP-1, setting it up lets the app draw "
                    + "how much is still in your system between doses and read your "
                    + "weight against it. Nothing here suggests a dose.",
                progress: nil,
                addLabel: "Set up medication",
                detailLabel: nil)
        }
        let effects = sideEffects == 0 ? ""
            : ", \(sideEffects) side \(SectionCaveat.plural(sideEffects, "effect"))"
        return ContributionSummary(
            isGrounded: true,
            figure: "\(doses) \(SectionCaveat.plural(doses, "dose"))",
            guidance: "\(doses) \(SectionCaveat.plural(doses, "dose")) logged\(effects). "
                + "Log each injection and how you felt, and the card can read what "
                + "changed against what you were on at the time.",
            progress: nil,
            addLabel: "Log a dose",
            detailLabel: {
                // The dated history — every dose and every side effect — is a
                // screen past the entry sheet, so this route earns a link the
                // moment there is anything for that screen to show.
                if doses > 0 {
                    return "All \(doses) \(SectionCaveat.plural(doses, "dose")) and side effects"
                }
                if sideEffects > 0 {
                    return "All \(sideEffects) side \(SectionCaveat.plural(sideEffects, "effect"))"
                }
                return nil
            }())
    }

    /// A file brought in from another app — today a Shotsy backup.
    ///
    /// `lastReceived` is a formatted phrase ("2 days ago"), not a `Date`: how a
    /// date reads belongs to the surface showing it, and keeping it a string is
    /// what lets this be tested without pinning a locale.
    ///
    /// "Grounded" is having ever received one. A log-shaped route with no
    /// target, like substances: inventing a cadence for re-importing a backup
    /// would be this view holding an opinion the model does not.
    public static func fileImport(lastReceived: String?) -> ContributionSummary {
        ContributionSummary(
            isGrounded: lastReceived != nil,
            figure: lastReceived ?? "None yet",
            guidance: lastReceived.map {
                "Last file received \($0). Sharing a fresh export keeps the "
                    + "imported history current — re-importing the same file is safe."
            } ?? "Shotsy holds your injections, weight and body composition. "
                + "Export its JSON and share it here — or pick a file you've "
                + "already saved.",
            progress: nil,
            addLabel: "Choose a file",
            detailLabel: nil)
    }

    /// The reader's own read of their build, against the app's estimate.
    ///
    /// Never "grounded" in the sense the others are — the estimate works without
    /// it, and an override is a correction rather than a missing input. So the
    /// seal is on whenever the app has something to show, and the guidance says
    /// what the override is *for* rather than asking for it.
    public static func bodyType(estimated: String?, override: String?) -> ContributionSummary {
        ContributionSummary(
            isGrounded: estimated != nil,
            figure: override ?? estimated ?? "No estimate yet",
            guidance: {
                if let override {
                    return "You've told the app you're \(override.lowercased()). It uses "
                        + "your word over its own estimate wherever the two differ."
                }
                if let estimated {
                    return "Estimated as \(estimated.lowercased()) from your own "
                        + "measurements. If you disagree, say so — the app takes your "
                        + "word over its estimate."
                }
                return "Needs a height and a weight before it can estimate your build. "
                    + "You can still set it yourself."
            }(),
            progress: nil,
            addLabel: override == nil ? "Set your build" : "Change your build",
            detailLabel: nil)
    }

    /// The reader's body measurements, from a tape or a scan.
    ///
    /// **Grounded means a waist exists**, not that every site does. The waist is
    /// what `BuildAssessmentModel` needs to move the card off BMI, and a summary
    /// that waited for a full set would report a card as ungrounded while it was
    /// already scoring on the better instrument.
    ///
    /// `lastMeasured` is a formatted phrase rather than a `Date`, so this stays
    /// testable without pinning a locale — the same shape `fileImport` uses.
    public static func bodyMeasurements(sitesMeasured: Int, hasWaist: Bool,
                                        lastMeasured: String?,
                                        isOverdue: Bool) -> ContributionSummary {
        ContributionSummary(
            isGrounded: hasWaist,
            figure: sitesMeasured > 0
                ? "\(sitesMeasured) measurement\(sitesMeasured == 1 ? "" : "s")"
                : "Nothing measured yet",
            guidance: {
                if !hasWaist {
                    return "A waist measurement is the one that counts here — it lets the "
                        + "card judge where your weight sits instead of guessing from BMI. "
                        + "A tape does the job; a scan takes the rest at the same time."
                }
                if isOverdue, let lastMeasured {
                    return "Last measured \(lastMeasured). Measuring about once a month is "
                        + "what turns single numbers into a trend — and taking it the same "
                        + "way each time is what makes two of them comparable."
                }
                if let lastMeasured {
                    return "Last measured \(lastMeasured). Your waist is feeding the card's "
                        + "score directly."
                }
                return "Your waist is feeding the card's score directly."
            }(),
            progress: nil,
            addLabel: sitesMeasured > 0 ? "Measure again" : "Add measurements",
            detailLabel: sitesMeasured > 0 ? "All measurements" : nil)
    }

    /// A day's screen time.
    ///
    /// `lastEntered` is a formatted phrase and `daysRecorded` the count, so this
    /// stays testable without pinning a locale — the same shape `fileImport`
    /// uses. "Grounded" is having enough days for the sleep model to contrast
    /// on; below that the app has readings but cannot yet answer the question
    /// they were entered for, and saying "all set" would be a promise it can't
    /// keep.
    public static func screenTime(daysRecorded: Int, needed: Int,
                                  lastEntered: String?) -> ContributionSummary {
        let enough = daysRecorded >= needed
        return ContributionSummary(
            isGrounded: enough,
            figure: daysRecorded == 0 ? "None yet"
                : "\(daysRecorded) \(SectionCaveat.plural(daysRecorded, "day"))",
            guidance: {
                guard daysRecorded > 0 else {
                    return "Apple won't let an app read your Screen Time, so this "
                        + "is the way in: read yesterday's total off Settings ▸ "
                        + "Screen Time, or have a Shortcut do it. With enough "
                        + "days the sleep card can ask whether tech time is what "
                        + "keeps you up."
                }
                if enough {
                    return "\(daysRecorded) days recorded\(lastEntered.map { ", last \($0)" } ?? ""). "
                        + "The sleep card contrasts your heavier screen days "
                        + "against the lighter ones — an association, never a cause."
                }
                return "\(daysRecorded) of \(needed) days needed before this can be "
                    + "read against how fast you fall asleep. Keep adding them and "
                    + "it starts on its own."
            }(),
            progress: enough || needed == 0 ? nil
                : Swift.min(1, Double(daysRecorded) / Double(needed)),
            addLabel: daysRecorded == 0 ? "Add a day" : "Add today's screen time",
            detailLabel: nil)
    }

    /// The reader's symptom tags, promoted from Apple Health.
    ///
    /// The one route with no in-app entry: tags are made in the Health app, so
    /// the button opens it rather than a sheet. A recorded absence is counted
    /// separately in the figure because it is a real answer, not silence —
    /// the same distinction `SymptomSeverity.isPresent` holds.
    public static func symptoms(tagged: Int, recordedAbsences: Int) -> ContributionSummary {
        let total = tagged + recordedAbsences
        return ContributionSummary(
            isGrounded: tagged > 0,
            figure: {
                guard total > 0 else { return "None yet" }
                let base = "\(tagged) tagged"
                return recordedAbsences > 0
                    ? base + " · \(recordedAbsences) marked absent" : base
            }(),
            guidance: "Tag symptoms in the Apple Health app (Browse ▸ Symptoms) "
                + "when you feel unwell. The radar grades itself against them — "
                + "and a day you record as not having something counts too, as "
                + "a recorded absence rather than silence.",
            progress: nil,
            addLabel: "Open Apple Health",
            detailLabel: total > 0
                ? "All \(total) symptom \(SectionCaveat.plural(total, "entry", plural: "entries"))"
                : nil)
    }

    /// The reader's name and emails — `ReaderIdentity`, B7 H1.
    ///
    /// "Grounded" is having said anything at all: a name alone answers the
    /// name-in-title question, emails alone answer the organiser one, and
    /// demanding both would nag for a completeness the classifier does not
    /// need. `name` is the reader's own and renders only on their device — the
    /// figure is the one place it appears outside the entry sheet.
    public static func readerIdentity(name: String?, emails: Int) -> ContributionSummary {
        let hasName = !(name ?? "").isEmpty
        let configured = hasName || emails > 0
        return ContributionSummary(
            isGrounded: configured,
            figure: {
                if let name, hasName { return name }
                return emails > 0
                    ? "\(emails) \(SectionCaveat.plural(emails, "email"))" : "Not set"
            }(),
            guidance: configured
                ? "The calendar reads events against who you are: an OOO block "
                    + "that names you — or that you organised — counts as your "
                    + "leave, and anyone else's is never counted as a meeting. "
                    + "Stays on this phone; never exported."
                : "Your name and emails let the calendar tell whose OOO block "
                    + "an event is — yours feeds your leave record, a "
                    + "colleague's stops counting as a meeting. Stays on this "
                    + "phone; never exported.",
            progress: nil,
            addLabel: configured ? "Update name & emails" : "Add your name & emails",
            detailLabel: nil)
    }

    /// The reader's supplement stack — Q8 / B3-25.
    ///
    /// "Grounded" is having one product, not a target number of them: the sum
    /// across a stack is what the card is for, but a single multivitamin is
    /// already a list of ingredients worth weighing, and setting a bottle count
    /// would be this view inventing a threshold the model does not have.
    ///
    /// ⚠️ **The figure names the unresolved ingredients whenever there are any**,
    /// and that is the one thing this summary does that the others do not. A
    /// stack with a proprietary blend in it can never be totalled exactly, and a
    /// "3 products" figure beside a card reporting floors would be the more
    /// reassuring of two true statements.
    public static func supplementStack(products: Int, nutrients: Int,
                                       unresolved: Int) -> ContributionSummary {
        ContributionSummary(
            isGrounded: products > 0,
            figure: {
                guard products > 0 else { return "None yet" }
                let base = "\(products) \(SectionCaveat.plural(products, "product"))"
                return unresolved > 0 ? base + " · \(unresolved) unstated" : base
            }(),
            guidance: {
                guard products > 0 else {
                    return "Nothing on this phone knows what is in a supplement "
                        + "bottle, so this is the one thing the app can only get "
                        + "from you. Type a Supplement Facts panel or scan it, "
                        + "and everything you take is added up ingredient by "
                        + "ingredient against the published upper intake limits."
                }
                let base = "\(products) \(SectionCaveat.plural(products, "product")) "
                    + "recorded, covering \(nutrients) "
                    + "\(SectionCaveat.plural(nutrients, "nutrient")) the app can "
                    + "weigh against a published limit."
                guard unresolved > 0 else {
                    return base + " Every ingredient declares an amount, so the "
                        + "totals are figures rather than floors."
                }
                return base + " \(unresolved) "
                    + "\(SectionCaveat.plural(unresolved, "ingredient")) declare "
                    + "no usable amount — a proprietary blend, or a unit that "
                    + "needs the form named — so those totals are floors and are "
                    + "shown as \"at least\"."
            }(),
            progress: nil,
            addLabel: products == 0 ? "Add a supplement" : "View & add supplements",
            detailLabel: products > 0
                ? "All \(products) \(SectionCaveat.plural(products, "product")) and what is in them"
                : nil)
    }

    /// Standing profile facts: one target, one count.
    public static func facts(set: Int, of total: Int) -> ContributionSummary {
        let complete = total > 0 && set >= total
        return ContributionSummary(
            isGrounded: complete,
            figure: "\(set) of \(total) set",
            guidance: complete
                ? "All set. The app has everything it asks for here — open it to "
                    + "check or change anything you entered."
                : "\(total - set) still to give. The more of these the app has, the "
                    + "less it has to assume.",
            progress: complete || total == 0 ? nil : Double(set) / Double(total),
            addLabel: complete ? "View your details" : "Add your details",
            detailLabel: nil)
    }
}
