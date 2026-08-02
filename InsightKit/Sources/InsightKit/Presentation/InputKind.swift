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
        }
    }

    /// Which heading it sits under.
    public var group: InputGroup {
        switch self {
        case .profileFacts: return .aboutYou
        case .cuffBloodPressure, .substanceEvent, .medicationDose, .sideEffect:
            return .asItHappens
        case .medicationRegimen: return .aboutYou
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
             .sideEffect, .bloodTestPhoto, .fileImport:
            return nil
        }
    }
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

public extension ContributionRoute {
    /// The master-list entry this card route corresponds to.
    ///
    /// Exhaustive on purpose: a new `ContributionRoute` cannot be added without
    /// naming its `InputKind`, so an input can never reach a card while being
    /// absent from the app's one complete list of inputs. That was the exact
    /// shape of the staleness the user reported.
    var inputKind: InputKind {
        switch self {
        case .bloodPressureReadings: return .cuffBloodPressure
        case .substanceLog: return .substanceEvent
        case .fileImport: return .fileImport
        case .groundingFacts: return .profileFacts
        }
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
