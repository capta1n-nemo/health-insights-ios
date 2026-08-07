import Foundation

/// A render-time cache for pure model passes, keyed by call site.
///
/// **A `nil` result is returned but never stored.** The cache exists to save
/// re-running whole models on every scrub and pan, and it clears whenever the
/// sample set changes — but a compute that runs during a transient window (a
/// rebuild that has just emptied the samples, a first render racing hydration)
/// can legitimately come back `nil`, and a cached `nil` is indistinguishable
/// from a fresh one. That is how "What you're made of" and "How you compare"
/// shipped claiming the user had no scale and no date of birth while both were
/// on screen two sections up: the section's *data* had arrived, and its cached
/// `nil` had not gone anywhere. A `nil` that recomputes each render costs one
/// model pass on an empty section; a `nil` that sticks costs a false sentence
/// until the next sync.
///
/// In InsightKit rather than `AppModel` because the caching rule *is* the
/// behaviour worth pinning, and the app target has no test target.
public struct RenderMemo {

    private var storage: [String: Any] = [:]

    public init() {}

    /// The cached value for `key`, or `compute()` — stored only when non-nil.
    ///
    /// The lookup unwraps the subscript **before** casting. `storage[key] as? T`
    /// looks right and is the original defect: for a missing key the subscript
    /// yields `Any?.none`, and a conditional cast of that to an optional `T`
    /// *succeeds* as `.some(.none)` — so every optional-typed compute "hit" a
    /// cached nil on its very first ask and never ran at all. That is what
    /// emptied "What you're made of" and "How you compare" the day render
    /// memoisation shipped, on a phone whose data was fine throughout.
    ///
    /// ## ⚠️ Never call this on a memo held in a stored property
    ///
    /// It is `mutating`, so calling it as `someObject.memo.value(key) { … }`
    /// holds an **exclusive access to `someObject.memo` for the whole of
    /// `compute()`**. A `compute` that memoises anything itself then asks for a
    /// second access to the same property, Swift's exclusivity checker traps,
    /// and the process takes `SIGABRT` — no exception, no message, nothing in
    /// the report but `swift_beginAccess → fatalError → abort`.
    ///
    /// That is backlog `D58`, diagnosed 2026-08-07 from two crash reports an
    /// hour and forty minutes apart with identical stacks: `SettlingSection`
    /// memoised `overnightCardiac`, whose `OvernightCardiacReading.build`
    /// memoises `nightSleepAllNights`. Every render of that section aborted the
    /// app.
    ///
    /// **`cached(_:)` + `store(_:_:)` below are the re-entrant-safe pair, and
    /// `AppModel.memoized` uses them.** This method survives for callers that
    /// own the memo as a local — where the hazard cannot arise — and for the
    /// tests that pin the two rules above.
    public mutating func value<T>(_ key: String, _ compute: () -> T) -> T {
        if let hit: T = cached(key) { return hit }
        let value = compute()
        store(key, value)
        return value
    }

    /// A cache lookup that holds **no** access once it returns.
    ///
    /// Non-mutating on purpose — see the warning on `value(_:_:)`. This is the
    /// half a re-entrant caller must use, because a read access ends at the
    /// return and cannot overlap the compute that follows.
    public func cached<T>(_ key: String) -> T? {
        guard let stored = storage[key], let hit = stored as? T else { return nil }
        return hit
    }

    /// Store a computed value, unless it is `nil`.
    ///
    /// The nil rule lives here rather than in `value(_:_:)` so that the
    /// re-entrant path cannot quietly lose it — a cached `nil` is the defect
    /// this type's own doc comment opens with.
    public mutating func store<T>(_ key: String, _ value: T) {
        guard !Self.isNil(value) else { return }
        storage[key] = value
    }

    public mutating func removeAll(keepingCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepingCapacity)
    }

    /// Whether a generic value is a `nil` optional.
    ///
    /// `Mirror`, not a protocol cast: `value as? SomeProtocol` on an optional
    /// *unwraps* it first, so a `.none` never reaches the conformance and the
    /// check silently answers "not nil" — which is exactly the bug this type
    /// exists to prevent, and how the first draft of this function failed its
    /// own test. A mirror reflects the optional as-is.
    private static func isNil<T>(_ value: T) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }
}
