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
    /// A photographed pathology report, read on-device.
    case bloodTestPhoto
    /// A backup file shared in from another app — today Shotsy's.
    case fileImport
    /// The reader's own read of their build, overriding the app's estimate.
    case bodyType

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .profileFacts: return "Your details"
        case .cuffBloodPressure: return "Blood-pressure reading"
        case .substanceEvent: return "Substance"
        case .medicationRegimen: return "Medication"
        case .medicationDose: return "Dose"
        case .sideEffect: return "Side effect"
        case .bloodTestPhoto: return "Blood test (photo)"
        case .fileImport: return "File from another app"
        case .bodyType: return "Your build"
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
            return "Photograph a pathology report; the values are read on-device and you confirm them."
        case .fileImport:
            return "Shotsy's JSON backup — injections, weight and body composition in one file."
        case .bodyType:
            return "Override the app's read of your build if you disagree with it. It estimates from your own measurements; you know your frame."
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
        case .fileImport: return "square.and.arrow.down"
        case .bodyType: return "figure.stand"
        }
    }

    /// Which heading it sits under.
    public var group: InputGroup {
        switch self {
        case .profileFacts: return .aboutYou
        case .cuffBloodPressure, .substanceEvent, .medicationDose, .sideEffect:
            return .asItHappens
        case .medicationRegimen, .bodyType: return .aboutYou
        case .bloodTestPhoto, .fileImport: return .bringItIn
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
        case .profileFacts, .cuffBloodPressure, .substanceEvent, .medicationRegimen,
             .sideEffect, .bloodTestPhoto, .fileImport, .bodyType:
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
        case .fileImport: return .offeredAndPrompted
        // An override of an estimate that already works without it. Offered, so
        // a reader who disagrees can find it; never nagged for, because the app
        // is not waiting on it.
        case .bodyType: return .offeredOnly
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
