import Foundation

/// Whether a number handed back by `JSONSerialization` was a JSON **boolean**.
///
/// `JSONSerialization` returns `true` as an `NSNumber`, so without this check
/// every boolean in a provider payload would be recorded as the number 1 or 0
/// and lose its type — which is what `RawValue.flag` exists to prevent.
///
/// Darwin distinguishes it by CoreFoundation type. swift-corelibs-foundation
/// has no `CFBoolean`, and `CFBooleanGetTypeID` is the second of exactly two
/// Darwin-only APIs that kept this package from building on Linux — which in
/// turn meant no agent sandbox could run `swift test`, and every logic error
/// had to be found by pushing and waiting for CI.
///
/// The Linux branch keys on the encoded `objCType`, **verified empirically on
/// Swift 6.0.3 / Ubuntu 24.04** rather than assumed:
///
/// | JSON      | objCType | boolValue |
/// | ---       | ---      | ---       |
/// | `true`    | `c`      | true      |
/// | `1`       | `i`      | true      |
/// | `1.5`     | `d`      | true      |
///
/// Note the third column: `boolValue` is no help at all, because it is true for
/// any non-zero number. The type code is the only signal.
@inline(__always)
func isJSONBoolean(_ number: NSNumber) -> Bool {
    #if canImport(Darwin)
    return CFGetTypeID(number) == CFBooleanGetTypeID()
    #else
    return String(cString: number.objCType) == "c"
    #endif
}
