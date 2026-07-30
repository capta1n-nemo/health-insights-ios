import Foundation

/// How a grounding fact stands right now: whether it is current, when it stops
/// being current, and what to say about it.
///
/// `requirementStatuses` has always returned `.satisfied` / `.stale` / `.missing`
/// and every caller threw away everything but `.missing`. So a value the user
/// gave was invisible until the moment it expired — no "your cholesterol is good
/// for another two months", no warning that a cuff reading was about to lapse,
/// just a prompt appearing one day out of nowhere for something that had been
/// quietly ageing for six.
public struct GroundingRenewal: Sendable, Equatable, Identifiable {

    public enum State: String, Sendable, Equatable {
        /// Recorded, current, and not close to lapsing.
        case current
        /// Recorded and current, but inside `expiringSoonFraction` of the end.
        case expiringSoon
        /// Past its freshness window. Still used — an old number is better than
        /// a population average — but no longer buying confidence.
        case stale
        /// Never recorded.
        case missing
    }

    public let kind: GroundingKind
    public let state: State
    /// When it was recorded, if it ever was.
    public let recordedAt: Date?
    /// When it stops being current. `nil` for facts that never go stale — a date
    /// of birth does not expire — and for facts never recorded at all.
    public let expiresAt: Date?
    /// Whether an insight marks this mandatory rather than a refinement.
    public let isMandatory: Bool

    public var id: GroundingKind { kind }

    /// Time left before it lapses. Negative once it has.
    public func timeRemaining(asOf now: Date) -> TimeInterval? {
        expiresAt.map { $0.timeIntervalSince(now) }
    }

    public init(kind: GroundingKind, state: State, recordedAt: Date?,
                expiresAt: Date?, isMandatory: Bool) {
        self.kind = kind
        self.state = state
        self.recordedAt = recordedAt
        self.expiresAt = expiresAt
        self.isMandatory = isMandatory
    }
}

public extension GroundingRenewal {

    /// How much of the freshness window has to be left before a value is called
    /// "expiring soon".
    ///
    /// A fifth, so the warning arrives proportionally: about three days before a
    /// cuff reading lapses and about five weeks before a lipid panel does. A
    /// fixed number of days would be either useless on the short window or
    /// permanent on the long one.
    static let expiringSoonFraction: Double = 0.2

    /// The state of one fact.
    static func evaluate(kind: GroundingKind, input: GroundingInput?,
                         isMandatory: Bool, now: Date) -> GroundingRenewal {
        guard let input else {
            return GroundingRenewal(kind: kind, state: .missing, recordedAt: nil,
                                    expiresAt: nil, isMandatory: isMandatory)
        }
        guard let window = kind.freshness else {
            // Never expires. A date of birth is not a thing to renew.
            return GroundingRenewal(kind: kind, state: .current, recordedAt: input.recordedAt,
                                    expiresAt: nil, isMandatory: isMandatory)
        }
        let expiry = input.recordedAt.addingTimeInterval(window)
        let remaining = expiry.timeIntervalSince(now)
        let state: State = remaining <= 0 ? .stale
            : (remaining <= window * expiringSoonFraction ? .expiringSoon : .current)
        return GroundingRenewal(kind: kind, state: state, recordedAt: input.recordedAt,
                                expiresAt: expiry, isMandatory: isMandatory)
    }

    /// One line describing where this fact stands.
    ///
    /// Deliberately plain about the stale case: the number keeps being used, and
    /// implying it has been discarded would be a second inaccuracy on top of the
    /// first.
    func sentence(asOf now: Date) -> String {
        switch state {
        case .missing:
            return isMandatory ? "Not recorded yet — needed for a full estimate."
                               : "Not recorded yet — optional, and improves accuracy."
        case .current:
            guard let remaining = timeRemaining(asOf: now) else {
                return "Recorded. This one doesn't expire."
            }
            return "Current for another \(Self.approximate(remaining))."
        case .expiringSoon:
            guard let remaining = timeRemaining(asOf: now) else { return "Current." }
            return "Due for renewal in \(Self.approximate(remaining))."
        case .stale:
            guard let remaining = timeRemaining(asOf: now) else { return "Out of date." }
            return "Out of date by \(Self.approximate(-remaining)) — still used, but it no longer counts as current."
        }
    }

    /// Rounded to the unit a person would use out loud. Nobody wants
    /// "13.4 days"; they want "2 weeks".
    static func approximate(_ interval: TimeInterval) -> String {
        let days = Swift.max(0, interval) / 86_400
        if days < 1 {
            let hours = Swift.max(1, Int((Swift.max(0, interval) / 3600).rounded()))
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        if days < 14 {
            let whole = Swift.max(1, Int(days.rounded()))
            return "\(whole) day\(whole == 1 ? "" : "s")"
        }
        if days < 60 {
            let weeks = Int((days / 7).rounded())
            return "\(weeks) week\(weeks == 1 ? "" : "s")"
        }
        let months = Swift.max(1, Int((days / 30.44).rounded()))
        return "\(months) month\(months == 1 ? "" : "s")"
    }
}

public extension InsightEngine {
    /// Every grounding fact any insight asks for, with where it stands.
    ///
    /// Unlike `outstandingGrounding`, this keeps the satisfied ones — which is
    /// the whole point. A renewal screen that only lists what is missing cannot
    /// tell you that everything is in order, and cannot warn you before it isn't.
    ///
    /// Sorted worst-first: missing, then stale, then expiring, then current;
    /// mandatory ahead of optional within each.
    func groundingRenewals(profile: UserHealthProfile,
                           now: Date = Date()) -> [GroundingRenewal] {
        var mandatoryByKind: [GroundingKind: Bool] = [:]
        for model in models {
            for requirement in model.requirements {
                mandatoryByKind[requirement.kind] =
                    (mandatoryByKind[requirement.kind] ?? false) || requirement.isMandatory
            }
        }
        return mandatoryByKind
            .map { kind, mandatory in
                GroundingRenewal.evaluate(kind: kind, input: profile.input(kind),
                                          isMandatory: mandatory, now: now)
            }
            .sorted { a, b in
                let order: [GroundingRenewal.State] = [.missing, .stale, .expiringSoon, .current]
                let ai = order.firstIndex(of: a.state) ?? 0
                let bi = order.firstIndex(of: b.state) ?? 0
                if ai != bi { return ai < bi }
                if a.isMandatory != b.isMandatory { return a.isMandatory }
                return a.kind.rawValue < b.kind.rawValue
            }
    }
}
