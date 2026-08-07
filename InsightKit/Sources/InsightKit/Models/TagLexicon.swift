import Foundation

/// **Placing a tag nobody has ever seen before.**
///
/// ## The requirement, and why a lookup table is not an answer
///
/// Oura lets a person invent a tag. So does every other app with the concept.
/// The reader's brief names *"Kayaking"* as the worked example precisely because
/// it is not on anybody's list — and a table of known tags would place it only
/// if somebody had thought of kayaking in advance, which is the same as saying
/// it would not place it.
///
/// So this classifier works on **word stems, not on tags**. `"kayak"` is one
/// entry and it places "Kayaking", "kayaked", "Kayak with Sam" and "kayaking
/// (rough water!)" — four strings, one of which is a sentence. A stem list is
/// still finite, but it is finite over *the language*, which is a very different
/// bet from finite over *the tags people invent*.
///
/// ## Three tiers, in order, and each says which one answered
///
/// 1. **The provider's own type code.** Oura's `tag_type_code` is a fixed,
///    vendor-controlled vocabulary (`tag_generic_alcohol`), so matching it is
///    the most reliable of the three — it is their concept, not our reading of
///    the reader's spelling.
/// 2. **This lexicon**, over the reader's own words. Deterministic, offline,
///    and the tier that has to hold: `SystemLanguageModel` is unavailable on
///    most devices this app runs on, and a feature that only works with Apple
///    Intelligence switched on is a feature the reader mostly does not have.
/// 3. **The on-device model**, for what is left — see `TagApplicabilityPrompt`,
///    which is asked *on the phone* and never over a network.
///
/// ## What it refuses to do
///
/// **A tie is `.unclassified`.** If two categories match equally the honest
/// answer is that this word is ambiguous, and it goes to the model (or stays
/// unplaced) rather than being awarded to whichever category happens to sort
/// first. "Bath" is genuinely both a recovery thing and nothing in particular;
/// pretending otherwise would put a wrong heading over the reader's own word.
public enum TagLexicon {

    /// Word stems per category. **Stems, not words** — matching is by prefix, so
    /// `"cycl"` covers cycling/cycled/cyclist and `"medit"` covers
    /// meditate/meditation/meditating.
    ///
    /// A stem earns its place by being *unambiguous within this set*. Words that
    /// are not — "shot" (a drink or a photograph), "bath", "session", "game",
    /// "weight" (lifted, or measured) — are deliberately absent: an ambiguous
    /// stem does not add coverage, it adds confident mistakes.
    static let stems: [TagApplicability: [String]] = [
        .activity: [
            "run", "jog", "walk", "hike", "hiking", "cycl", "bike", "biking", "ride",
            "swim", "kayak", "canoe", "paddl", "row", "ski", "snowboard", "skat",
            "surf", "climb", "bould", "gym", "workout", "training", "train session",
            "exercis", "yoga", "pilates", "sport", "football", "soccer", "tennis",
            "padel", "squash", "badminton", "golf", "basketball", "cricket", "rugby",
            "hockey", "boxing", "martial", "karate", "judo", "jiu", "wrestl",
            "danc", "zumba", "crossfit", "hiit", "spin class", "peloton", "treadmill",
            "marathon", "triathlon", "sprint", "steps", "stairs", "deadlift",
            "squat", "bench press", "lifting", "calisthen", "rowing", "erg",
        ],
        .sleepRecovery: [
            "sleep", "slept", "nap", "bedtime", "early night", "late night",
            "lie in", "rest day", "recover", "sauna", "cold plunge", "ice bath",
            "massage", "physio", "insomnia", "snor", "restless", "woke", "wake",
            "earplug", "eye mask", "blackout", "disturbed",
        ],
        .mentalHealth: [
            "stress", "anxi", "anxious", "panic", "mood", "sad", "depress",
            "calm", "relax", "medit", "mindful", "breathwork", "therap",
            "counsell", "overwhelm", "burnout", "lonely", "angry", "irritab",
            "grief", "journal", "gratitude", "worried", "tense", "low mood",
            "mental health", "cry",
        ],
        .illness: [
            "sick", "ill", "unwell", "cold symptoms", "flu", "fever", "cough",
            "sneez", "headache", "migraine", "nausea", "vomit", "diarrh",
            "sore throat", "sore", "infect", "covid", "virus", "allerg",
            "hayfever", "hay fever", "pain", "ache", "cramp", "injur", "sprain",
            "symptom", "congest", "sinus", "rash", "dizzy", "bloat",
        ],
        .substances: [
            "alcohol", "drink", "drank", "beer", "wine", "prosecco", "champagne",
            "whisk", "vodka", "gin", "rum", "tequila", "cocktail", "pint",
            "hangover", "caffein", "coffee", "espresso", "latte", "energy drink",
            "nicotine", "smok", "vape", "cigar", "cannabis", "weed", "nightcap",
        ],
        .nutrition: [
            "meal", "ate", "eating", "food", "breakfast", "lunch", "dinner",
            "brunch", "snack", "fasting", "fasted", "diet", "carb", "protein",
            "sugar", "hydrat", "water intake", "calorie", "keto", "vegan",
            "vegetarian", "takeaway", "restaurant", "overate", "overeat",
            "cheat meal", "big meal",
        ],
        .medication: [
            "medic", "medication", "pill", "tablet", "dose", "dosed", "antibiot",
            "ibuprofen", "paracetamol", "acetaminophen", "aspirin", "statin",
            "ssri", "antihistamine", "supplement", "vitamin", "magnesium",
            "creatine", "melatonin", "injection", "jab", "vaccin", "inhaler",
            "prescription",
        ],
        .social: [
            "friend", "family", "party", "social", "date night", "birthday",
            "wedding", "funeral", "visit", "guest", "kids", "children",
            "argument", "celebrat", "concert", "gig", "night out", "pub",
            "reunion", "anniversary",
        ],
        .travel: [
            "travel", "flight", "flying", "flew", "plane", "airport", "jetlag",
            "jet lag", "long drive", "road trip", "hotel", "airbnb", "holiday",
            "vacation", "trip", "timezone", "time zone", "abroad", "camping",
        ],
        .work: [
            "work", "meeting", "deadline", "shift", "night shift", "overtime",
            "presentation", "exam", "revision", "studying", "study", "oncall",
            "on call", "office", "wfh", "commut", "interview", "conference",
            "email", "launch day",
        ],
    ]

    /// Prefixes providers put on their own machine codes, stripped before
    /// matching so `tag_generic_alcohol` is looked at as "alcohol".
    static let codePrefixes = ["tag_generic_", "tag_special_", "tag_"]

    /// Codes that carry no meaning of their own — Oura's marker for "this is a
    /// tag the reader invented", where the name is the only thing that says
    /// anything.
    static let meaninglessCodes: Set<String> = ["custom", "generic", "tag", "other", "none"]

    // MARK: - The public entry point

    /// Place a tag. **Never throws and never returns nil** — `.unclassified` is
    /// the answer when nothing matched, and it is a real answer.
    ///
    /// - Parameters:
    ///   - name: the reader's own words.
    ///   - code: the provider's machine code, if it gave one.
    public static func classify(name: String, code: String? = nil) -> TagApplicabilityMapping {
        // Tier 1 — the provider's own vocabulary. Tried first because it is
        // fixed and vendor-controlled: `tag_generic_alcohol` means alcohol in
        // every account on earth, whereas "a couple" means it only here.
        if let code, let bare = meaningfulCode(code) {
            if let hit = bestMatch(in: tokens(from: bare)) {
                return TagApplicabilityMapping(
                    applicability: hit.applicability, method: .providerCode,
                    confidence: 0.85,
                    rationale: "Your device files this under its own type “\(code)”, and “\(hit.stem)” is a \(hit.applicability.rawValue.lowercased()) word.")
            }
        }
        // Tier 2 — the reader's words.
        guard let hit = bestMatch(in: tokens(from: name)) else {
            return .unresolved
        }
        return TagApplicabilityMapping(
            applicability: hit.applicability, method: .lexicon,
            confidence: hit.confidence,
            rationale: "Matched “\(hit.stem)” in “\(name)”.")
    }

    // MARK: - Matching

    /// How far ahead the winning category must be, as a fraction of its own
    /// score, before the match counts as decided. Below this the tag goes to the
    /// on-device model — or stays unplaced, which is still a true answer.
    ///
    /// Set at 0.15 so that **more matched stems decides and stem length does
    /// not**: a second match in the same category adds half a point (~33%
    /// margin, decisive), whereas one stem against one stem differs only by the
    /// length bonus (a few percent, ambiguous). "Went for a run at the gym, then
    /// a beer" is Activity; "Kayaking with a glass of wine after" is genuinely
    /// about both and says so.
    static let decisiveMargin = 0.15

    struct Hit {
        let applicability: TagApplicability
        let stem: String
        let confidence: Double
    }

    /// The words of a tag, plus the whole phrase, lowercased.
    ///
    /// The phrase is kept alongside the words because several stems are two
    /// words long ("jet lag", "night out") and a token stream alone cannot see
    /// them. Splitting is on anything that is not a letter or a digit, and on
    /// camel-case boundaries, so `lateNight`, `late_night` and `Late Night` all
    /// arrive as the same pair.
    static func tokens(from text: String) -> [String] {
        var spaced = ""
        var previousWasLower = false
        for ch in text {
            if ch.isUppercase && previousWasLower { spaced.append(" ") }
            previousWasLower = ch.isLowercase || ch.isNumber
            spaced.append(ch.isLetter || ch.isNumber ? ch : " ")
        }
        let lowered = spaced.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let words = lowered.split(separator: " ").map(String.init)
        let phrase = words.joined(separator: " ")
        return phrase.isEmpty ? [] : words + [phrase]
    }

    /// The single best category, or `nil` when nothing matched **or when two
    /// categories matched equally well**.
    ///
    /// ⚠️ The tie branch is the important one. Without it the winner would be
    /// whichever category `Dictionary` happened to iterate first — a stable
    /// answer, arrived at for no reason, presented to the reader as a heading
    /// over their own word.
    static func bestMatch(in tokens: [String]) -> Hit? {
        guard !tokens.isEmpty else { return nil }
        var scores: [TagApplicability: (score: Double, stem: String)] = [:]
        for (applicability, stems) in stems {
            for stem in stems where matches(stem, in: tokens) {
                // A longer stem is more specific evidence than a short one:
                // "marathon" says more than "run".
                let weight = 1 + Double(stem.count) / 100
                let current = scores[applicability]
                if current == nil || weight > current!.score {
                    scores[applicability] = (weight, stem)
                } else {
                    scores[applicability] = (current!.score + weight / 2, current!.stem)
                }
            }
        }
        let ranked = scores.sorted { $0.value.score > $1.value.score }
        guard let top = ranked.first else { return nil }
        let runnerUp = ranked.count > 1 ? ranked[1].value.score : 0
        let margin = min((top.value.score - runnerUp) / max(top.value.score, 0.0001), 1)
        // ⚠️ **A *near* tie is ambiguous, not just an exact one.** This guard was
        // first written as `abs(difference) < 0.0001`, and a test caught that it
        // could essentially never fire: the length weighting means two matched
        // categories almost always differ by a hair, so "wine dinner" —
        // substances and nutrition, one stem each — resolved to nutrition
        // because "dinner" is two letters longer than "wine". A guard that only
        // catches a mathematically exact tie is a guard that never runs, which
        // is worse than none: it reads as protection while every genuinely
        // ambiguous tag is being awarded on a coin toss.
        guard margin >= Self.decisiveMargin else { return nil }
        // Confidence rises with the margin over the runner-up, and is capped
        // below the provider-code tier: this is a word match, not a statement
        // by the vendor.
        return Hit(applicability: top.key, stem: top.value.stem,
                   confidence: min(0.4 + 0.35 * margin, 0.75))
    }

    /// Whether a stem is present. Prefix matching on a word, or substring
    /// matching on the whole phrase for the multi-word stems.
    static func matches(_ stem: String, in tokens: [String]) -> Bool {
        if stem.contains(" ") {
            return tokens.contains { $0.contains(stem) }
        }
        return tokens.contains { $0.hasPrefix(stem) }
    }

    /// A provider code with its prefix removed, or `nil` when the code says
    /// nothing (Oura's `custom`).
    static func meaningfulCode(_ code: String) -> String? {
        var bare = code.lowercased(with: Locale(identifier: "en_US_POSIX"))
        for prefix in codePrefixes where bare.hasPrefix(prefix) {
            bare = String(bare.dropFirst(prefix.count))
            break
        }
        guard !bare.isEmpty, !meaninglessCodes.contains(bare) else { return nil }
        return bare
    }
}
