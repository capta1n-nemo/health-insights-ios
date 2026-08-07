import Foundation

// MARK: - The grounding facts

/// **A person who does not exist.**
///
/// Several cards cannot produce a number from measurements alone: a
/// cardiovascular risk needs an age, a sex and a lipid panel; a biological age
/// needs an age to compare against; a composition velocity needs to know what
/// the reader is *trying* to do with their weight. None of that can be sensed,
/// so a simulator with a full set of vitals and an empty profile still shows
/// several cards asking for details — which is exactly the "cards where there is
/// no data" the reader saw on 2026-08-07.
///
/// ⚠️ **These are invented numbers about nobody**, chosen so each card lands
/// somewhere legible rather than at an extreme. `docs/privacy-and-ip.md` governs
/// what may be written down here: the shape of a thing, never a reading. There
/// is no reading here to be careful with — there is no person.
public extension GroundingKind {

    /// **The exhaustive rule, for the profile.** A new `GroundingKind` does not
    /// compile until it says what a seeded simulator should hold for it — or why
    /// it should hold nothing.
    ///
    /// - Parameter now: `dateOfBirth` is stored as an epoch, so the fixture's
    ///   age is only stable if it is computed against the same clock the app
    ///   will read it with.
    func syntheticSeedFact(asOf now: Date) -> SyntheticSeed.Fact {
        switch self {
        // 41 years old. Old enough that ASCVD and SCORE2 will both run (both
        // have a floor at 40), young enough that no card is pinned to its top
        // band by age alone.
        case .dateOfBirth:
            return .value(now.addingTimeInterval(-41 * 365.2425 * 24 * 3600).timeIntervalSince1970)
        case .biologicalSex:   return .value(0)      // male — see `UserHealthProfile.sex`
        case .ascvdRaceGroup:  return .value(0)      // white / other
        case .score2Region:    return .value(1)      // moderate — the UK's own band
        // mmol/L. A total a little above the guideline with an unremarkable HDL,
        // so the risk cards score in their middle rather than at either end: a
        // fixture that scored "optimal" would leave every band above it
        // unreachable on a simulator.
        case .totalCholesterol: return .value(5.4)
        case .hdlCholesterol:   return .value(1.25)
        case .currentSmoker:    return .value(0)
        case .hasDiabetes:      return .value(0)
        case .onBPMedication:   return .value(0)
        // ⚠️ **Deliberately not equal to the seeded cuff *samples*.** The Blood
        // Pressure card shows a measured reading beside a modelled estimate, and
        // if the two were identical a screenshot could not tell which figure it
        // was looking at — the same discipline `SyntheticSeed.lutealOffsets`
        // applies against the literature priors, for the same reason.
        case .cuffSystolic:  return .value(126)
        case .cuffDiastolic: return .value(80)
        // The seeded weight trend is down, so the goal has to be `lose` or the
        // composition card scores a fictional person's deliberate progress as an
        // unexplained wasting.
        case .weightGoal: return .value(WeightGoal.lose.rawValue)
        }
    }
}

public extension SyntheticSeed {

    /// A grounding fact the seed writes, or a stated reason for writing none.
    enum Fact: Sendable {
        case value(Double)
        case notSeeded(String)
    }

    /// Every grounding fact a seeded simulator should hold, ready for
    /// `DataStore.saveGrounding(kind:value:)`.
    static func profileFacts(asOf now: Date = Date()) -> [GroundingKind: Double] {
        var out: [GroundingKind: Double] = [:]
        for kind in GroundingKind.allCases {
            if case .value(let value) = kind.syntheticSeedFact(asOf: now) { out[kind] = value }
        }
        return out
    }

    /// The same, as the profile the models actually take — so a test can judge
    /// a card exactly as the app will render it.
    static func profile(asOf now: Date = Date()) -> UserHealthProfile {
        var profile = UserHealthProfile()
        for (kind, value) in profileFacts(asOf: now) {
            profile.set(GroundingInput(kind: kind, value: value, recordedAt: now))
        }
        return profile
    }
}

// MARK: - What each card should show

/// **The card-level half of the rule.**
///
/// Metric coverage is necessary and not sufficient: a card can have every series
/// it reads and still show nothing, because what it is waiting for is a substance
/// log, a symptom tag or a calendar. Two cards shipped *invisible* on 2026-08-03
/// with green tests and green CI, and the simulator is the tool that catches that
/// class — so an empty card on a seeded simulator has to be **declared**, or the
/// next reader cannot tell a card that is waiting from a card that is broken.
///
/// The paired test asserts this switch in **both** directions. A card declared
/// `scores` that stops scoring fails, which is the regression guard; a card
/// declared `needsMore` that starts scoring *also* fails, which is what stops a
/// stale excuse outliving the gap it described.
public extension SyntheticSeed {
    enum CardExpectation: Sendable {
        /// The seed gives this card a number: it renders populated on a seeded
        /// simulator, and a screenshot of it is worth taking.
        case scores
        /// It does not, and this is what it is waiting for. Never "no data" —
        /// the reason has to name the thing and, where one exists, the route
        /// that would supply it.
        case needsMore(String)
    }
}

public extension InsightID {

    /// **The exhaustive rule, for cards.** A new `InsightID` does not compile
    /// until it says what a seeded simulator shows for it.
    var syntheticSeedExpectation: SyntheticSeed.CardExpectation {
        switch self {

        // Scored from vitals plus the seeded grounding facts.
        case .cardiovascularRisk: return .scores
        case .heartHealth:        return .scores
        case .bloodPressure:      return .scores
        case .bodyComposition:    return .scores
        case .fitness:            return .scores
        case .sleep:              return .scores
        case .readiness:          return .scores
        case .energy:             return .scores
        case .nutrition:          return .scores
        case .metabolism:         return .scores
        case .sustainedLoad:      return .scores
        case .gait:               return .scores
        case .biologicalAge:      return .scores
        case .mentalHealth:       return .scores
        case .soundExposure:      return .scores
        // **Scores, and the first draft of this switch said it did not.** The
        // guess was that a radar with no symptom tags has nothing to grade —
        // wrong: it scores the vitals against the reader's own baseline and
        // reaches its top band ("nothing converging") without a single tag. The
        // tags enrich it rather than gate it. Left as a comment because it is
        // the one entry here that was *corrected by the test*, which is the
        // whole argument for asserting this switch in both directions.
        case .symptomRadar:       return .scores

        // MARK: The three that samples cannot reach
        //
        // These declare `readsOnlySamples == false`: their inputs are
        // construction state bound by `InsightEngine.withSubstanceLog` and
        // `withCalendar`, and none of it is a `HealthMetricSample`. A samples
        // fixture leaves them empty through no fault of their own, and the
        // reason has to be written here rather than guessed at from a blank card.
        //
        // ⚠️ `HealthWatchModel` also declares `readsOnlySamples == false` (for
        // its tags) and still scores — so this list is *not* the same as that
        // flag, and deriving it from the flag would put a false excuse on the
        // radar. That is the mistake this switch caught on itself.
        case .substanceImpact:
            return .needsMore("""
                A substance log. The events live in SwiftData, not in samples, and \
                are rebound by InsightEngine.withSubstanceLog. Until the seed writes \
                one, this card shows its invite state — and so does \
                MetricType.activeMedicationLevel, which is modelled from those doses.
                """)
        case .workImpact:
            return .needsMore("""
                A calendar. Bound by InsightEngine.withCalendar. The whole card is a \
                busy-working-day against quiet-working-day comparison, and nothing \
                on a simulator knows which days were busy.
                """)
        case .travelDrain:
            return .needsMore("""
                A calendar with travel in it. The app records no location and no time \
                zone on any reading, so a calendar entry is the only thing that knows \
                the reader moved — see the card's own note.
                """)
        // Same gate as work impact and travel drain, and for the same reason:
        // its exposure side is the calendar — events, attendees, formality — and
        // a seeded simulator has none. ⚠️ **Its third question is gated harder
        // still**: "does contact restore or drain *you*" is a per-person
        // direction, and no fixture can carry an answer that is by definition
        // learned from one reader's own record. A seed that made it score would
        // be seeding the conclusion.
        case .socialBattery:
            return .needsMore("""
                A calendar with people in it. The card reads events, attendees and \
                formality as its exposure side, and a seeded simulator has no \
                calendar — so the depletion comparison has nothing to compare.
                """)
        }
    }
}
