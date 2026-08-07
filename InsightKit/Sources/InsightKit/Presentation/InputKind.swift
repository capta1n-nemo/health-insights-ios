import Foundation

/// Every way a reader can put something *into* this app.
///
/// ## Why this exists
///
/// The app had four places that offered inputs — Settings' "Your details", the
/// Today `+` menu, a card's "View & add" section, and a Settings row for the
/// blood-test photo — and each one was a hand-written list. So each went stale
/// separately. On 2026-08-02 Settings still offered nine facts while the app
/// accepted fourteen kinds of input: the weight goal shipped that morning and
/// appeared in none of them; medication, doses, side effects and the Shotsy
/// file reached only one surface each. The user, looking at that screen:
/// *"This master input list is now out of date, so many new things that could
/// be input are missing, make sure it gets updated every time a new input is in
/// the app."*
///
/// **"Make sure" cannot mean "remember".** It is the same failure `DataDomain`
/// was created for one commit earlier, one level up: `DataDomain` guarantees
/// every kind of data can be *seen*, `InputKind` guarantees every kind of data
/// can be *given*. Both are enums with exhaustive switches at the surfaces,
/// because the app target has no test target and the compiler is the only thing
/// that can hold a rule there.
///
/// A new input adds a case here, and then does not build until it has said its
/// title, its explanation, which group it belongs in, and what it opens.
public enum InputKind: String, Sendable, CaseIterable, Identifiable {
    /// The standing facts the clinical models need — one screen, many facts,
    /// because they are all the same shape and a row each would bury the rest.
    case profileFacts
    /// A dated pair of cuff numbers.
    case cuffBloodPressure
    /// One entry in the dated substance log.
    case substanceEvent
    /// Starting (or changing) a GLP-1 regimen.
    case medicationRegimen
    /// One injection.
    case medicationDose
    /// Something the reader felt, with how strongly.
    case sideEffect
    /// A pathology report brought in as a document — photographed, scanned with
    /// the camera, or picked as a PDF. Read entirely on-device.
    ///
    /// ⚠️ **One case for three routes, and the reader is the reason.** Asked
    /// whether bloods should be typed or photographed (backlog `Q7`), they
    /// answered *"both? What do you mean? We should be able to accept all of
    /// these."* All four routes exist; what is split is where the *conversation*
    /// divides, and it divides between "I have the paperwork" (this) and "I have
    /// the numbers" (`labResultManual`). Camera, scanner and PDF are one choice
    /// made inside one sheet, exactly as `bodyMeasurements` is one case for a
    /// tape and a scan.
    case bloodTestPhoto
    /// Blood-test values typed in.
    ///
    /// The floor, not the ceiling: lipids and HbA1c have their own fields and
    /// anything else the reader's report prints can be entered by naming the
    /// analyte. Separate from `bloodTestPhoto` because a reader holding a
    /// printout and a reader holding a phone are answering different questions,
    /// and because this is the route that still works when a scan comes back
    /// unreadable — which the import screen's failure message points at.
    case labResultManual
    /// An ECG brought in as a photo or a PDF, with its metadata.
    ///
    /// ⚠️ **Import, store, display. Never interpret** — see `ECGRecord`. The
    /// input exists so a trace lives with the rest of the reader's health data;
    /// nothing in this app reads the waveform.
    case ecgImport
    /// A backup file shared in from another app — today Shotsy's.
    case fileImport
    /// The reader's own read of their build, overriding the app's estimate.
    case bodyType
    /// A day's screen time, in minutes.
    ///
    /// **Entered rather than sensed, and that is forced.** Apple sandboxes the
    /// Screen Time API so no third-party app can read the figure into its own
    /// model — see `MetricType.screenTimeMinutes`. The reader reads it off
    /// Settings ▸ Screen Time, or has a Shortcuts automation supply it.
    case screenTime
    /// Body measurements — a tape today, a camera/LiDAR scan once that ships.
    ///
    /// One input for both, deliberately. They produce the same thing (a
    /// `BodyScan`), they answer the same question, and splitting them would put
    /// two near-identical rows on every surface while the reader is choosing
    /// between "get the tape out" and "stand in front of the phone" — which is
    /// a choice inside the sheet, not a different kind of data.
    case bodyMeasurements
    /// The reader's name and emails — `ReaderIdentity`, backlog B7 H1.
    ///
    /// **One case for the whole conversation** — name, work emails, personal
    /// emails, one sheet — for the reason `.bodyMeasurements` is one case: they
    /// answer one question ("who are you, to your calendar?") and three
    /// near-identical rows would bury it. Strings, so it is not a grounding
    /// fact; see `ReaderIdentity` for why it cannot live in the profile.
    case readerIdentity
    /// One period of leave, entered by hand — backlog B7 H4. Past or planned:
    /// *"I should also be able to input holidays that are planned manually."*
    case holiday
    /// **Telling the app what a flagged half-hour actually was** — backlog P32.
    ///
    /// An input like any other, and it belongs on this list for the reason the
    /// list exists: the app takes something from the reader, so every input
    /// surface has to know about it or it becomes the next feature reachable
    /// from exactly one screen.
    ///
    /// **One case for confirm and correct**, for the reason `.bodyMeasurements`
    /// is one case: they answer one question ("what was this?") in one sheet,
    /// and two near-identical rows would bury it. The distinction between
    /// agreeing and disagreeing is kept where it is measurable —
    /// `FlaggedEventJudgement`, which stores the guess and the answer apart.
    case eventConfirmation
    /// **A supplement, its Supplement Facts panel, and how much you take** —
    /// backlog Q8 / B3-25.
    /// ⚠️ **The one input in this whole enum with no alternative source.** Every
    /// other row here is a fact the app could in principle receive some other
    /// way — a file, a photograph, a connected provider. Nothing anywhere senses
    /// a supplement: no wearable, no scale, and Apple Health has no concept of a
    /// supplement product. The reader typing it is not a fallback, it is the
    /// mechanism.
    /// One case for bottle, panel and servings, for the reason
    /// `.bodyMeasurements` is one case for a tape and a scan: they are one
    /// screen answering one question, and three rows would bury it.
    case supplement
    /// **Telling the app what a day actually was, when it has guessed** —
    /// backlog `B11-2`.
    ///
    /// The reader's own framing: *"an estimated sickness they can correct —
    /// type and severity, similar to how you can correct a work or travel event
    /// (same concept - then we can learn from it)."* So it is `.eventConfirmation`'s
    /// twin, one level up: the app guesses about a day, the reader answers, and
    /// the guess and the answer are stored apart so accuracy stays measurable.
    ///
    /// **One case for confirm and correct**, for the reason `.eventConfirmation`
    /// is one: they answer one question ("what was this day?") in one sheet, and
    /// two near-identical rows would bury it.
    case illnessCorrection

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .profileFacts: return "Your details"
        case .cuffBloodPressure: return "Blood-pressure reading"
        case .substanceEvent: return "Substance"
        case .medicationRegimen: return "Medication"
        case .medicationDose: return "Dose"
        case .sideEffect: return "Side effect"
        case .bloodTestPhoto: return "Blood test (photo, scan or PDF)"
        case .labResultManual: return "Blood test results (typed)"
        case .ecgImport: return "ECG"
        case .fileImport: return "File from another app"
        case .bodyType: return "Your build"
        case .screenTime: return "Screen time"
        case .bodyMeasurements: return "Body measurements"
        case .readerIdentity: return "Name & emails"
        case .holiday: return "Holiday or leave"
        case .eventConfirmation: return "Confirm a flagged event"
        case .supplement: return "Supplement"
        case .illnessCorrection: return "Were you ill?"
        }
    }

    /// What it is for, in the reader's terms. Shown under the row, because a
    /// list of eight nouns does not tell anyone which one they want.
    public var detail: String {
        switch self {
        case .profileFacts:
            return "Age, sex, cholesterol, smoking, diabetes and your weight goal — the facts a phone cannot sense."
        case .cuffBloodPressure:
            return "A systolic/diastolic pair from a real cuff. Calibrates the cuffless estimate."
        case .substanceEvent:
            return "Caffeine, alcohol, nicotine or anything else you want measured against your vitals."
        case .medicationRegimen:
            return "A GLP-1 you're taking, and when you started. Used to draw how much is still active."
        case .medicationDose:
            return "One injection: how much, and when."
        case .sideEffect:
            return "What you felt and how strongly, so it can be read against your doses."
        case .bloodTestPhoto:
            return "Photograph, scan or pick a PDF of a pathology report. Every analyte on it is read on this device and you confirm each one — nothing is uploaded."
        case .labResultManual:
            return "Type the numbers yourself. Cholesterol and HbA1c have their own fields; anything else your report prints can be entered by name."
        case .ecgImport:
            return "A photo or PDF of an ECG, kept with its date, device and whatever was printed on it. This app stores and shows a trace; it never interprets one."
        case .fileImport:
            return "Shotsy's JSON backup — injections, weight and body composition in one file."
        case .bodyMeasurements:
            return "Waist, hips, chest and the rest — from a tape, or a scan. A waist is what lets the body composition card stop guessing from BMI."
        case .bodyType:
            return "Override the app's read of your build if you disagree with it. It estimates from your own measurements; you know your frame."
        case .screenTime:
            return "Yesterday's total from Settings ▸ Screen Time. Apple won't let an app read it, so this is the way in — and it lets the sleep card ask whether tech time is what's keeping you up."
        case .readerIdentity:
            return "Your name, work and personal emails. Lets the calendar tell whose meeting — and whose OOO block — an event is. Stays on this phone and is never exported."
        case .holiday:
            return "Time off, past or planned. Goes into one leave record beside what your calendar shows, so the app can know how long since you last had any."
        case .eventConfirmation:
            return "The app flags stretches where your heart rate ran high with nothing moving to explain it, and guesses what they were. Tell it what actually happened — the guess and your answer are kept apart, so it can show you how often it's right."
        case .illnessCorrection:
            return "The app guesses what a day was from your overnight signals and whatever you recorded, and it is wrong far more often than it is right. Tell it what actually happened — the guess and your answer are kept apart, so it can show you how often it is right, and a day you mark as illness joins your sick-day record."
        case .supplement:
            return "A bottle you take, and what its Supplement Facts panel says. Nothing senses a supplement, so this is the only way in — and once several are in, every ingredient is added up across them and shown against the published upper intake limits for your age."
        }
    }

    public var symbolName: String {
        switch self {
        case .profileFacts: return "person.text.rectangle"
        case .cuffBloodPressure: return "heart.text.square"
        case .substanceEvent: return "pills"
        case .medicationRegimen: return "cross.vial"
        case .medicationDose: return "syringe"
        case .sideEffect: return "waveform.path.ecg.rectangle"
        case .bloodTestPhoto: return "doc.text.viewfinder"
        case .labResultManual: return "list.clipboard"
        case .ecgImport: return "waveform.path.ecg"
        case .fileImport: return "square.and.arrow.down"
        case .bodyType: return "figure.stand"
        case .screenTime: return "iphone"
        case .bodyMeasurements: return "figure.mixed.cardio"
        case .readerIdentity: return "person.crop.circle"
        case .holiday: return "beach.umbrella"
        case .eventConfirmation: return "questionmark.bubble"
        case .supplement: return "pills"
        case .illnessCorrection: return "bandage"
        }
    }

    /// Which heading it sits under.
    public var group: InputGroup {
        switch self {
        case .profileFacts: return .aboutYou
        // A holiday is a dated entry like a substance or a dose — logged as it
        // happens (or as it is booked), not a standing fact.
        case .cuffBloodPressure, .substanceEvent, .medicationDose, .sideEffect,
             .screenTime, .holiday,
             // Answering a flag is a dated act about a dated window, not a
             // standing fact — the same shape as logging a substance, entered
             // again and again.
             .eventConfirmation,
             // Answering "was I ill on Tuesday" is a dated act about a dated
             // day, the same shape as answering a flagged window.
             .illnessCorrection:
            return .asItHappens
        // Identity is entered once and changed rarely — the profile's shape,
        // even though it is not a grounding fact.
        // A supplement is a standing fact about the reader — what they take,
        // changed when a bottle changes — and not a dated event. Beside the
        // medication regimen for the same reason it sits beside it everywhere
        // else: both are "what am I on", entered once and revisited.
        case .medicationRegimen, .bodyType, .bodyMeasurements, .readerIdentity,
             .supplement:
            return .aboutYou
        // Typed values are dated entries like a cuff reading — logged when the
        // results arrive, not a standing fact about the reader.
        case .labResultManual: return .asItHappens
        case .bloodTestPhoto, .fileImport, .ecgImport: return .bringItIn
        }
    }

    /// Whether the row only makes sense once something else exists.
    ///
    /// Only doses: logging one before naming the medication has nothing to
    /// attach to. Returned as a reason rather than a `Bool` so the surface can
    /// say *why* instead of silently omitting a row — an input that vanishes is
    /// indistinguishable from one that was never built, which is the confusion
    /// this whole type exists to end.
    public var unavailableReason: String? {
        switch self {
        case .medicationDose: return "Set up a medication first."
        // ⚠️ **One list, reconstructed by hand after a merge.** Three agents
        // added kinds to this switch on the same day and an automatic
        // keep-both resolution spliced two `case` lists together, leaving a
        // fragment that still compiled as far as the eye but not the parser.
        // If this list ever looks duplicated again, that is what happened.
        case .profileFacts, .cuffBloodPressure, .substanceEvent, .medicationRegimen,
             .sideEffect, .bloodTestPhoto, .fileImport, .bodyType, .screenTime,
             .bodyMeasurements, .readerIdentity, .holiday, .labResultManual,
             .ecgImport, .supplement, .illnessCorrection:
            return nil
        // ⚠️ **`nil`, deliberately, even though there is often nothing to
        // answer.** Making the row unavailable when the queue is empty was the
        // first draft and it is the shape rule 7 was written against: a surface
        // that disappears for want of data is indistinguishable from one that
        // was never built. The feed opens either way and its own empty state
        // says what the detector is waiting for — which is the honest version
        // and the one the reader can act on.
        //
        // It would also be a lie half the time it fired. `unavailableReason`'s
        // only consumer treats a non-nil value as "no medication yet"
        // (`AddDataView.isBlocked`), so a second conditional kind would have
        // been blocked by the *medication* test.
        case .eventConfirmation:
            return nil
        }
    }
}

public extension InputKind {
    /// **Where this input has to be reachable from, and whether to ask for it.**
    ///
    /// The rule the user set on 2026-08-02, after finding three inputs on the
    /// Body Composition card that its "View & add" section did not mention:
    /// *"if manual input is allowed on a card, it must be in the View and add
    /// sub menu of the card, in the + master add button, in the add or update
    /// section of the settings sub menu; if it's missing, or hasn't been added
    /// for the first time, it goes into the improve your health recommendation
    /// that can be dismissed."*
    ///
    /// Two of those four are already structural — the `+` menu and the Settings
    /// screen are both generated from `InputKind.allCases`, so an input cannot
    /// be missing from either. This is the other two. It is exhaustive, so a new
    /// input has to say which it is, and `InputKindTests` checks the claim
    /// against every shipped model's `contributions` rather than trusting it.
    var cardRequirement: CardRequirement {
        switch self {
        // Prompted per *fact* by `SuggestionEngine.unlocks`, which knows which
        // card each one is blocking — a second, vaguer "add your details" would
        // be the same nudge with less information.
        case .profileFacts: return .offeredOnly
        // Same: `cuffSystolic` is a grounding requirement, so the specific
        // prompt already exists.
        case .cuffBloodPressure: return .offeredOnly
        case .substanceEvent: return .offeredAndPrompted
        case .medicationRegimen: return .offeredAndPrompted
        // Gated on a regimen existing — `unavailableReason` says so — and
        // prompting for a dose before there is anything to dose is nonsense.
        case .medicationDose: return .offeredOnly
        // Nobody should be nudged into recording a side effect they have not
        // had. It is offered wherever the medication is, and that is enough.
        case .sideEffect: return .offeredOnly
        case .bloodTestPhoto:
            return .settingsOnly("It fills the same cholesterol facts the "
                + "profile route already offers, so a card carrying both would "
                + "ask twice for one number.")
        // Same reasoning as `.bloodTestPhoto` above, and one addition that is a
        // date rather than a principle: **no shipped card reads the general lab
        // store.** The two lipids reach the risk models as grounding facts, and
        // that is the route a card should offer. The other thirty analytes have
        // no card at all yet, so offering the sheet on one would claim a
        // sensitivity nothing has.
        case .labResultManual:
            return .settingsOnly("The lipids it can fill are already offered by "
                + "the profile route, and no shipped card reads the wider lab "
                + "store yet — a card offering it would claim a sensitivity its "
                + "model does not have. The offer moves onto a card in the same "
                + "change that wires one.")
        // ⚠️ **Not a date, a principle.** Nothing scores an ECG here and nothing
        // will: interpreting a trace is a regulated device claim. A card exists
        // to say what a number means, so an ECG has no card to be offered on —
        // and there is no future change that would give it one.
        case .ecgImport:
            return .settingsOnly("No card takes an ECG, and none will. "
                + "Interpreting a trace is a regulated device claim; this app "
                + "imports, stores and shows one, which is a Data-tab job "
                + "rather than a scoring one.")
        case .fileImport: return .offeredAndPrompted
        // An override of an estimate that already works without it. Offered, so
        // a reader who disagrees can find it; never nagged for, because the app
        // is not waiting on it.
        case .bodyType: return .offeredOnly
        // Offered on the Sleep card, and prompted for while never used: it is
        // the one input that turns "is it tech time?" from a question the model
        // names as unanswerable into one it can actually contrast.
        case .screenTime: return .offeredAndPrompted
        // Prompted, and it is the clearest case in this switch: a waist
        // measurement is the one input that moves Body Composition off BMI —
        // `BuildAssessmentModel` cannot run without it — and until one exists
        // the card is scoring on the weakest instrument it has. The 30-day
        // re-scan nudge is separate and comes from `BodyScanCadence`.
        case .bodyMeasurements: return .offeredAndPrompted
        // On the Work impact card (`ContributionRoute.readerIdentity`), because
        // identity is what decides whose OOO block a work day contains — the
        // card whose numbers it moves is where the reader will wonder about it.
        // Offered, never prompted: the classifier runs without it, an unnamed
        // OOO is already never counted as work, and nagging someone to type
        // their own name is how a prompt gets dismissed forever.
        case .readerIdentity: return .offeredOnly
        // Settings (and the `+` menu) only, for now — and the reason is a date,
        // not a principle: **no shipped card reads the holiday ledger yet.**
        // B7 H6 wires work impact, travel, stress and mental health to
        // `daysSinceLastLeave`, each with a `modelVersion` bump, and the card
        // offer belongs in that change — a card offering an input its model
        // ignores would be claiming a sensitivity it does not have.
        // ⚠️ **Settings and the `+` menu only, and the reason is a date rather
        // than a principle** — the same call `.holiday` makes below.
        //
        // **No shipped card reads a confirmed event yet.** The judgements are
        // stored, the accuracy is computed and the Data tab renders all of it,
        // but nothing scores off a confirmed cause. A card offering the input
        // would be claiming a sensitivity its model does not have, which is the
        // one thing `ContributionRoute` must never be used to imply. The offer
        // moves onto the cards — Readiness and Health Watch are the obvious
        // pair, since a confirmed cause is exactly what would let them stop
        // counting an evening as an unexplained departure — in the same change
        // that wires them, with a `modelVersion` bump.
        //
        // ⚠️ **This is not the same as being unprompted.** The reader's own
        // condition on this feature was a dismissible front-page suggestion, and
        // it exists: `SuggestionEngine.eventsAwaitingReview` raises the queue
        // itself, and `SuggestionEngine.locationPermission` raises the missing
        // permission. Both are better-founded than the generic
        // "you-have-not-tried-this" row `.offeredAndPrompted` would produce —
        // they carry a count and a reason — which is why routing through
        // `unusedInputs` would have been a downgrade rather than the rule.
        case .eventConfirmation:
            return .settingsOnly("No shipped card scores off a confirmed event "
                + "yet, so a card offering the input would claim a sensitivity "
                + "its model has not got. The feed is reached from the Data tab, "
                + "the + menu and its own dismissible suggestions instead.")
        // Prompted, and it is the one input where the prompt is the only way
        // the reader would learn the feature exists. Every other input answers a
        // question the app is visibly already asking; nothing on any screen
        // hints that this app can add a stack of labels up, and a card the
        // reader never opens cannot tell them.
        case .supplement: return .offeredAndPrompted
        // ⚠️ **Settings and the `+` menu only, and here the reason genuinely is
        // a principle rather than a date.** The symptom radar *does* score off
        // this input — a correction joins `SickDayLedger`, which
        // `ReportedIllness` reads (B11-8) — so the usual "no card reads it yet"
        // argument does not apply and the card offer would be honest.
        //
        // It is still wrong, because **the question cannot be asked without a
        // day attached to it.** A button on the card would have to invent one,
        // and "today" is the worst possible default for this input: today is the
        // day the reader has least often finished having. The question belongs
        // where the day is already named — the per-day sick page, reached from
        // the log and the calendar (`SickDayDetailView`) — and the `+` menu
        // entry opens that page on today rather than asking in the abstract.
        //
        // ⚠️ **Not the same as being unprompted.** Nagging somebody to say
        // whether they were ill is the one nudge this app must never send: it is
        // a question about their body, raised by a detector whose prospective
        // positive predictive value is 4–12%, and a dismissible "you have not
        // tried this" row about illness would be exactly the accusation
        // `docs/illness-detection-evidence-2026-08-07.md` forbids.
        case .illnessCorrection:
            return .settingsOnly("The question is always about a particular day, "
                + "so it is asked on that day's page — reached from the sick-day "
                + "log and calendar. A button on the card would have to guess "
                + "which day you meant.")
        case .holiday:
            return .settingsOnly("No shipped card reads the holiday ledger yet "
                + "(B7 H6). Offering the log on a card whose score ignores it "
                + "would claim a sensitivity the model does not have; the offer "
                + "moves onto the cards in the same change that wires them.")
        // **Promoted with B7 H6 (2026-08-08), exactly as the `settingsOnly`
        // reason it replaces promised.** Four cards now score time since the
        // reader's last leave — Work impact, Travel drain, Stress load and
        // Mental health — so `.holidayLog` reaches all four and the input is
        // offered where its numbers move.
        // ⚠️ **Offered, never prompted.** A never-used holiday log earns no
        // dismissible row, and the reason is the one guard `LeaveRecency` is
        // built around: with nothing entered the cards score nothing off it and
        // say so, so there is no hole for a nudge to be filling. Nagging
        // somebody to tell an app about their holidays is also a poor use of the
        // one prompt slot a card gets.
        case .holiday: return .offeredOnly
        }
    }

    /// Whether a card must offer it at all.
    var mustBeOfferedOnACard: Bool {
        switch cardRequirement {
        case .offeredAndPrompted, .offeredOnly: return true
        case .settingsOnly: return false
        }
    }

    /// Whether never having used it earns a dismissible prompt.
    var promptsWhenNeverUsed: Bool {
        if case .offeredAndPrompted = cardRequirement { return true }
        return false
    }
}

/// Where an input has to be reachable from.
public enum CardRequirement: Sendable, Equatable {
    /// On a card's "View & add", and prompted for while it has never been used.
    case offeredAndPrompted
    /// On a card's "View & add", but never prompted — an override or a
    /// refinement nobody should be nagged about.
    case offeredOnly
    /// Reachable from Settings alone, for the stated reason.
    case settingsOnly(String)
}

/// The headings the master input list is organised under.
public enum InputGroup: String, Sendable, CaseIterable, Identifiable {
    /// Standing facts and set-up — entered once, changed rarely.
    case aboutYou
    /// Dated events — entered again and again.
    case asItHappens
    /// Data that already exists somewhere else.
    case bringItIn

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .aboutYou: return "About you"
        case .asItHappens: return "Log as it happens"
        case .bringItIn: return "Bring data in"
        }
    }

    public var footer: String {
        switch self {
        case .aboutYou:
            return "Entered once and reused. A value past its window keeps being used — it just stops counting as current."
        case .asItHappens:
            return "Dated entries. Each one is read against the vitals around it."
        case .bringItIn:
            return "Nothing is uploaded. Files and photos are read on this phone."
        }
    }

    /// The kinds under this heading, in `InputKind`'s own case order.
    public var kinds: [InputKind] {
        InputKind.allCases.filter { $0.group == self }
    }
}


public extension GroundingKind {
    /// Whether this fact gets its own row in "Your details".
    ///
    /// Exhaustive rather than a hand-kept array. The array version lived in
    /// `SettingsView`, listed nine of twelve kinds, and silently dropped
    /// `weightGoal` the day it shipped — so Body Composition asked for a goal
    /// the settings screen had no way to set.
    ///
    /// The one `false` is diastolic, which is not a separate fact: a cuff
    /// reading is one event with two numbers, entered together.
    var isEnteredDirectly: Bool {
        switch self {
        case .cuffDiastolic: return false
        case .dateOfBirth, .biologicalSex, .ascvdRaceGroup, .score2Region,
             .totalCholesterol, .hdlCholesterol, .currentSmoker, .hasDiabetes,
             .onBPMedication, .cuffSystolic, .weightGoal:
            return true
        }
    }

    /// Every fact that earns a row, in declaration order.
    static var directlyEntered: [GroundingKind] {
        allCases.filter(\.isEnteredDirectly)
    }
}
