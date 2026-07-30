import Foundation

/// One leaf value pulled out of a provider payload, with the dotted path that
/// located it (`"contributors.sleep_recovery"`, `"spo2_percentage.average"`).
public struct FlatField: Sendable, Hashable {
    public let path: String
    public let value: RawValue

    public init(path: String, value: RawValue) {
        self.path = path
        self.value = value
    }
}

/// Something the flattener chose not to store, and why. Recorded rather than
/// dropped silently: "we ingest 100% of the payload" is only a claim worth
/// making if the exceptions are counted and visible in the diagnostics log.
public struct SkippedField: Sendable, Hashable {
    public enum Reason: String, Sendable, Hashable {
        case null                // JSON null carries no measurement
        case emptyArray
        case depthLimit
        case arrayTruncated      // kept the first N elements
        case stringTruncated     // kept the first N characters
        case unsupportedType
    }
    public let path: String
    public let reason: Reason

    public init(path: String, reason: Reason) {
        self.path = path
        self.reason = reason
    }
}

/// How deep and how literally to unpack a payload.
public struct FlattenPolicy: Sendable {
    /// What to do with an array of scalars.
    public enum ArrayStrategy: String, Sendable {
        /// Emit `.count` / `.min` / `.max` / `.mean` / `.first` / `.last`.
        /// The default, because a provider's intra-day series (Oura's 5-minute
        /// night heart rate is ~200 values per record) multiplies the store by
        /// two orders of magnitude for data Apple Health already mirrors.
        case summarise
        /// Emit every element as `path.0`, `path.1`, … Literal, and expensive.
        case expand
    }

    public var maxDepth: Int
    public var maxStringLength: Int
    public var arrayStrategy: ArrayStrategy
    /// Cap on elements unpacked from an array of objects, and on `.expand`.
    public var maxArrayElements: Int

    public init(maxDepth: Int = 5,
                maxStringLength: Int = 4096,
                arrayStrategy: ArrayStrategy = .summarise,
                maxArrayElements: Int = 64) {
        self.maxDepth = maxDepth
        self.maxStringLength = maxStringLength
        self.arrayStrategy = arrayStrategy
        self.maxArrayElements = maxArrayElements
    }

    public static let `default` = FlattenPolicy()
}

/// Turns an arbitrary decoded-JSON object into a flat list of typed leaf values.
///
/// Provider-agnostic by construction: it knows nothing about Oura, Withings or
/// HealthKit, only about JSON. That is what lets a new connector arrive with no
/// parser of its own — describe its envelope and this walks whatever it returns,
/// including fields that didn't exist when the code was written.
public enum JSONFlattener {

    public struct Output: Sendable {
        public var fields: [FlatField] = []
        public var skipped: [SkippedField] = []
    }

    /// Flatten a JSON value. `prefix` is prepended to every path; pass `""` for
    /// a record root.
    public static func flatten(_ json: Any,
                               prefix: String = "",
                               policy: FlattenPolicy = .default,
                               skipping ignoredKeys: Set<String> = []) -> Output {
        var out = Output()
        walk(json, path: prefix, depth: 0, policy: policy, ignoredKeys: ignoredKeys, into: &out)
        return out
    }

    private static func walk(_ json: Any,
                             path: String,
                             depth: Int,
                             policy: FlattenPolicy,
                             ignoredKeys: Set<String>,
                             into out: inout Output) {
        if json is NSNull {
            out.skipped.append(SkippedField(path: path, reason: .null))
            return
        }

        // Scalars. String truncation is recorded so an unusually large payload
        // field can't quietly lose its tail.
        if let scalar = RawValue(json: json) {
            if case .text(let s) = scalar, s.count > policy.maxStringLength {
                out.fields.append(FlatField(path: path, value: .text(String(s.prefix(policy.maxStringLength)))))
                out.skipped.append(SkippedField(path: path, reason: .stringTruncated))
            } else {
                out.fields.append(FlatField(path: path, value: scalar))
            }
            return
        }

        guard depth < policy.maxDepth else {
            out.skipped.append(SkippedField(path: path, reason: .depthLimit))
            return
        }

        if let object = json as? [String: Any] {
            // Sorted so a payload's field order can't reorder the output, which
            // keeps diagnostics and tests stable.
            for key in object.keys.sorted() where !ignoredKeys.contains(key) {
                guard let value = object[key] else { continue }
                walk(value, path: join(path, key), depth: depth + 1,
                     policy: policy, ignoredKeys: ignoredKeys, into: &out)
            }
            return
        }

        if let array = json as? [Any] {
            walkArray(array, path: path, depth: depth, policy: policy,
                      ignoredKeys: ignoredKeys, into: &out)
            return
        }

        out.skipped.append(SkippedField(path: path, reason: .unsupportedType))
    }

    private static func walkArray(_ array: [Any],
                                  path: String,
                                  depth: Int,
                                  policy: FlattenPolicy,
                                  ignoredKeys: Set<String>,
                                  into out: inout Output) {
        guard !array.isEmpty else {
            out.skipped.append(SkippedField(path: path, reason: .emptyArray))
            return
        }

        // A numeric series — Oura's `heart_rate.items`, `hrv.items`, `met.items`.
        // Nulls inside these are gaps in the recording, not values.
        let numbers = array.compactMap { element -> Double? in
            guard let n = element as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            return n.doubleValue
        }
        let nulls = nullCount(array)
        if numbers.count == array.count || (numbers.count > 0 && numbers.count + nulls == array.count) {
            // Gaps in a recorded series are counted once for the array rather
            // than once per element — the accounting has to stay honest without
            // producing an entry for every missing five-minute slot.
            if nulls > 0 { out.skipped.append(SkippedField(path: path, reason: .null)) }
            switch policy.arrayStrategy {
            case .summarise:
                summarise(numbers, total: array.count, path: path, into: &out)
            case .expand:
                let kept = min(array.count, policy.maxArrayElements)
                for (i, value) in numbers.prefix(kept).enumerated() {
                    out.fields.append(FlatField(path: join(path, String(i)), value: .number(value)))
                }
                if array.count > kept {
                    out.skipped.append(SkippedField(path: path, reason: .arrayTruncated))
                }
                // Keep the summary alongside the points so charts and thresholds
                // don't have to re-derive it.
                summarise(numbers, total: array.count, path: path, into: &out)
            }
            return
        }

        // Anything else — objects, strings, mixtures — is unpacked element by
        // element up to the cap.
        let kept = min(array.count, policy.maxArrayElements)
        for i in 0..<kept {
            walk(array[i], path: join(path, String(i)), depth: depth + 1,
                 policy: policy, ignoredKeys: ignoredKeys, into: &out)
        }
        if array.count > kept {
            out.skipped.append(SkippedField(path: path, reason: .arrayTruncated))
        }
    }

    private static func summarise(_ numbers: [Double], total: Int, path: String, into out: inout Output) {
        out.fields.append(FlatField(path: join(path, "count"), value: .number(Double(total))))
        guard let first = numbers.first, let last = numbers.last,
              let lowest = numbers.min(), let highest = numbers.max() else { return }
        let mean = numbers.reduce(0, +) / Double(numbers.count)
        out.fields.append(FlatField(path: join(path, "min"), value: .number(lowest)))
        out.fields.append(FlatField(path: join(path, "max"), value: .number(highest)))
        out.fields.append(FlatField(path: join(path, "mean"), value: .number(mean)))
        out.fields.append(FlatField(path: join(path, "first"), value: .number(first)))
        out.fields.append(FlatField(path: join(path, "last"), value: .number(last)))
    }

    private static func nullCount(_ array: [Any]) -> Int {
        array.reduce(into: 0) { count, element in if element is NSNull { count += 1 } }
    }

    private static func join(_ path: String, _ component: String) -> String {
        path.isEmpty ? component : "\(path).\(component)"
    }
}
