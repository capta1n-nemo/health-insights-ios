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
    public mutating func value<T>(_ key: String, _ compute: () -> T) -> T {
        if let stored = storage[key], let hit = stored as? T { return hit }
        let value = compute()
        if !Self.isNil(value) { storage[key] = value }
        return value
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
