import Foundation

/// **What the reader is taking, ingredient by ingredient** — backlog Q8, B3-25.
///
/// ## Why the reader types it
///
/// Nothing on a phone knows what is in a supplement bottle. No wearable senses
/// it, HealthKit has no concept of a supplement product, and the dietary
/// micronutrient series it does carry are for *food* and are almost always
/// empty. The reader's own answer to "worth the one-time capture?" was *"Yes?
/// From where?"*, and the answer is: from them, off the label — because there
/// is no other source and there is not going to be one.
///
/// ## The part nobody ships
///
/// Capturing a bottle is not the feature. Every multivitamin is a *list*, and
/// the finding is the sum **across the stack** — a multivitamin, a separate
/// zinc, and a "immune support" blend can each be unremarkable and add to more
/// zinc than the published limit. That is what `SupplementStackModel` computes
/// and what `SupplementStackInsight` reports.
///
/// ## ⚠️ A proprietary blend is not zero
///
/// US labelling permits a "proprietary blend" to declare a total and withhold
/// the per-ingredient split. That is common, and the wrong thing to do with it
/// is the easy thing: treat the missing amount as nought and report a total
/// that looks precise. `IngredientAmount` therefore has three cases and only one
/// of them is a number — everything downstream carries the unknowns beside the
/// total, and `NutrientTotal.isComplete` is false wherever any exist.
public struct SupplementProduct: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    /// What it says on the front of the bottle.
    public var name: String
    public var brand: String?
    /// What the label calls one serving — "2 capsules", "1 scoop".
    public var servingDescription: String?
    /// Everything the Supplement Facts panel declares, **per serving**.
    public var ingredients: [SupplementIngredient]
    /// Where the ingredient list came from, which is what decides how much to
    /// trust it.
    public var source: LabelSource
    public var addedAt: Date

    public init(id: UUID = UUID(), name: String, brand: String? = nil,
                servingDescription: String? = nil,
                ingredients: [SupplementIngredient],
                source: LabelSource = .typedByReader,
                addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.brand = brand
        self.servingDescription = servingDescription
        self.ingredients = ingredients
        self.source = source
        self.addedAt = addedAt
    }

    /// Where an ingredient list came from.
    ///
    /// ⚠️ **Provenance is not decoration here.** A list the reader typed off a
    /// bottle in their hand is the strongest evidence available; a list matched
    /// from a label database is a claim about a product with the same name, and
    /// the formulation may have changed. The card says which, per product.
    public enum LabelSource: Codable, Sendable, Hashable {
        /// Typed off the bottle. **The offline path, and the primary one.**
        case typedByReader
        /// Read off a photograph of the Supplement Facts panel by
        /// `SupplementLabelParser`, and confirmed by the reader before it was
        /// saved. Carries nothing about the photograph — the image is never kept.
        case scannedLabel
        /// Matched against a record in the NIH Dietary Supplement Label
        /// Database, by its DSLD id. See `DSLDReference`.
        case dsld(id: String, retrievedAt: Date)

        public var displayName: String {
            switch self {
            case .typedByReader: return "You typed it"
            case .scannedLabel: return "Scanned from the label"
            case .dsld: return "NIH label database"
            }
        }

        /// The caveat that belongs beside a total built from this source.
        public var caveat: String? {
            switch self {
            case .typedByReader, .scannedLabel:
                return nil
            case .dsld(let id, let retrievedAt):
                return "Matched to NIH label database record \(id) on "
                    + "\(retrievedAt.formatted(date: .abbreviated, time: .omitted)). "
                    + "That is what the label said when it was catalogued — "
                    + "check it against the bottle you have, because "
                    + "formulations change and the database is a snapshot."
            }
        }
    }
}

/// One line of a Supplement Facts panel.
public struct SupplementIngredient: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    /// The nutrient, where the line names one this app can weigh. `nil` for the
    /// many that it cannot — a herb, an amino acid, a probiotic strain — which
    /// are kept rather than dropped, because a stack the reader cannot recognise
    /// as theirs is one they will not trust.
    public var nutrient: Nutrient?
    /// The label's own words, always kept. For an unrecognised line this is all
    /// there is; for a recognised one it is what the reader will look for.
    public var labelText: String
    public var amount: IngredientAmount

    public init(id: UUID = UUID(), nutrient: Nutrient?, labelText: String,
                amount: IngredientAmount) {
        self.id = id
        self.nutrient = nutrient
        self.labelText = labelText
        self.amount = amount
    }
}

/// **How much of an ingredient a serving contains — or why that is not known.**
///
/// ⚠️ The two non-numeric cases are the point of this type. A label listing a
/// proprietary blend gives no per-ingredient amounts, and a label that lists an
/// ingredient with no figure at all is not unheard of. Neither may silently
/// become zero.
public enum IngredientAmount: Codable, Sendable, Hashable {
    /// The label declared a figure.
    case stated(NutrientAmount)
    /// The ingredient is inside a proprietary blend: the blend's own total may
    /// be declared, but this ingredient's share of it is not.
    case withinProprietaryBlend(blendName: String, blendTotal: NutrientAmount?)
    /// Listed with no amount at all.
    case notStated

    public var stated: NutrientAmount? {
        if case .stated(let amount) = self { return amount }
        return nil
    }

    /// Whether this contributes a knowable number to a sum.
    public var isKnown: Bool { stated != nil }

    /// What to print where a figure would go.
    public var displayText: String {
        switch self {
        case .stated(let amount):
            return SupplementFormatting.amount(amount.value, unit: amount.unit)
        case .withinProprietaryBlend(let name, let total):
            guard let total else { return "Unstated — in the \(name) blend" }
            return "Unstated — in the \(name) blend, "
                + "\(SupplementFormatting.amount(total.value, unit: total.unit)) in total"
        case .notStated:
            return "Unstated"
        }
    }
}

/// One product in the reader's stack, and how much of it they take.
///
/// Separate from `SupplementProduct` because a bottle and a regimen are
/// different facts with different lifetimes: the label does not change when the
/// reader halves their dose, and a product they stopped taking is still the
/// product it was. Same reasoning as `MedicationSchedule` against a compound.
public struct SupplementEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var product: SupplementProduct
    /// Servings per day, as the reader takes it. Fractional on purpose — half a
    /// scoop and one-capsule-of-a-two-capsule-serving are both ordinary.
    public var servingsPerDay: Double
    public var startedOn: Date
    /// `nil` while they are still taking it.
    public var stoppedOn: Date?

    public init(id: UUID = UUID(), product: SupplementProduct,
                servingsPerDay: Double = 1, startedOn: Date = Date(),
                stoppedOn: Date? = nil) {
        self.id = id
        self.product = product
        self.servingsPerDay = servingsPerDay
        self.startedOn = startedOn
        self.stoppedOn = stoppedOn
    }

    public func isActive(on date: Date) -> Bool {
        guard startedOn <= date else { return false }
        guard let stoppedOn else { return true }
        return stoppedOn > date
    }
}

// MARK: - The label database

/// **The NIH Dietary Supplement Label Database, and what depending on it costs.**
///
/// The brief named DSLD as the ingredient-list source and asked, before anything
/// was built on it, whether it is genuinely free. Checked 2026-08-07:
///
/// - **Licence: CC0 1.0 Universal.** A public-domain dedication, published by
///   the NIH Office of Dietary Supplements. No attribution is required and none
///   of the data is copyrightable by anyone downstream — which is the strongest
///   answer this question can have.
/// - **No API key is documented**, and none is required to read the endpoints.
/// - **No rate limit is published.** The guide's only operational note is that
///   result sets are large and callers should ask for small pages. An
///   unpublished limit is not the same as none, so anything built on it has to
///   tolerate being refused.
///
/// ⚠️ **So the licence is not the risk; the dependency is.** An unversioned,
/// unkeyed, rate-limit-unstated public service is exactly the thing that will be
/// unavailable on the evening someone wants to add a bottle — and this app's own
/// premise is that it works on the reader's phone with their data. **A supplement
/// stack must not need a network to add up.**
///
/// ## Therefore
///
/// **Nothing in this feature calls DSLD, and the summation never could.**
/// `SupplementStackModel` reads `[SupplementEntry]` out of local storage, and
/// `NutrientUpperLimits` is a table compiled into the binary. Both work in
/// aeroplane mode, forever, and neither degrades if this service is retired.
///
/// A DSLD lookup is a *convenience for capture only* — one fewer panel to type —
/// and `SupplementProduct.LabelSource.dsld` is the shape a matched product takes
/// when one is added. This type holds the endpoint and the terms so the next
/// session does not have to re-establish them; the client itself is deliberately
/// not built yet, because the typed and scanned paths are complete without it
/// and a half-wired network dependency is worse than none.
public enum DSLDReference {
    public static let baseURL = "https://api.ods.od.nih.gov/dsld/v9"
    public static let licence = "CC0 1.0 Universal (public domain dedication)"
    public static let requiresAPIKey = false
    public static let guideURL = "https://dsld.od.nih.gov/api-guide"

    /// What a reader is told wherever a lookup is offered.
    public static let disclosure =
        "Looking a product up asks the US National Institutes of Health label "
        + "database, which is free and public. It sends the product name and "
        + "nothing about you. Everything already in your stack adds up without "
        + "it, on this phone, with no network at all."
}

// MARK: - Formatting

/// Number formatting shared by the model, the card and the entry sheet.
///
/// In InsightKit rather than in a view because the app target has no test
/// target, and because a total printed one way on a card and another way in the
/// Data tab is how two screens come to disagree about one number.
public enum SupplementFormatting {

    /// A quantity with its unit, at a precision that suits its size. 0.9 mcg
    /// and 1,100 mcg both have to read correctly, and one format cannot do both.
    public static func amount(_ value: Double, unit: NutrientUnit) -> String {
        "\(number(value)) \(unit.symbol)"
    }

    public static func number(_ value: Double) -> String {
        // A whole number prints whole. "40.0 mg" beside "a published upper
        // limit of 40 mg" would be the same figure written two ways on one
        // screen, and most label amounts are integers.
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        let magnitude = abs(value)
        if magnitude >= 100 { return String(format: "%.0f", value) }
        if magnitude >= 10 { return String(format: "%.1f", value) }
        if magnitude >= 1 { return String(format: "%.2f", value) }
        return String(format: "%.3f", value)
    }

    /// A share of an upper limit as a percentage.
    public static func percent(_ fraction: Double) -> String {
        fraction >= 0.1 ? String(format: "%.0f%%", fraction * 100)
                        : String(format: "%.1f%%", fraction * 100)
    }
}
