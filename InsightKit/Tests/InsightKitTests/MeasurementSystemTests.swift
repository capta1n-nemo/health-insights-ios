import XCTest
@testable import InsightKit

/// The units audit, as assertions.
///
/// Every test here is a wrong number somebody could have shipped: a waist typed
/// in inches and stored as centimetres, a US lipid panel typed into a mmol/L
/// box, a temperature *deviation* shifted by 32 degrees.
final class MeasurementSystemTests: XCTestCase {

    // MARK: - Locale resolution

    func testRegionParsingHandlesTheIdentifierShapesFoundationProduces() {
        XCTAssertEqual(MeasurementSystem.region(of: Locale(identifier: "en_GB")), "GB")
        XCTAssertEqual(MeasurementSystem.region(of: Locale(identifier: "en-US")), "US")
        XCTAssertEqual(MeasurementSystem.region(of: Locale(identifier: "en_US_POSIX")), "US")
        XCTAssertEqual(MeasurementSystem.region(of: Locale(identifier: "zh-Hant-TW")), "TW")
        // A bare language has no region, and must not be mistaken for one.
        XCTAssertEqual(MeasurementSystem.region(of: Locale(identifier: "fr")), "")
    }

    func testBritainIsNeitherMetricNorImperial() {
        XCTAssertEqual(MeasurementSystem.resolved(.automatic, locale: Locale(identifier: "en_GB")),
                       .britishHybrid)
        XCTAssertEqual(MeasurementSystem.resolved(.automatic, locale: Locale(identifier: "en_US")),
                       .usCustomary)
        XCTAssertEqual(MeasurementSystem.resolved(.automatic, locale: Locale(identifier: "fr_FR")),
                       .metric)
        XCTAssertEqual(MeasurementSystem.resolved(.automatic, locale: Locale(identifier: "en_AU")),
                       .metric)
    }

    func testAnExplicitPreferenceIgnoresTheLocale() {
        XCTAssertEqual(MeasurementSystem.resolved(.metric, locale: Locale(identifier: "en_US")),
                       .metric)
        XCTAssertEqual(MeasurementSystem.resolved(.usCustomary, locale: Locale(identifier: "en_GB")),
                       .usCustomary)
    }

    // MARK: - The arithmetic

    func testConversionsMatchTheDefiningConstants() {
        // 1 lb ≡ 0.45359237 kg, so 100 kg is 220.462… lb.
        XCTAssertEqual(DisplayUnit.pounds.fromCanonical(100), 220.462262, accuracy: 0.0001)
        // 1 in ≡ 2.54 cm.
        XCTAssertEqual(DisplayUnit.inches.fromCanonical(86.36), 34, accuracy: 0.0001)
        // A height stored in metres.
        XCTAssertEqual(DisplayUnit.inchesFromMetres.fromCanonical(1.8542), 73, accuracy: 0.0001)
        // 1 mile ≡ 1.609344 km.
        XCTAssertEqual(DisplayUnit.miles.fromCanonical(5), 3.106856, accuracy: 0.0001)
        XCTAssertEqual(DisplayUnit.fahrenheit.fromCanonical(37), 98.6, accuracy: 0.0001)
        XCTAssertEqual(DisplayUnit.usFluidOunces.fromCanonical(2), 67.628, accuracy: 0.001)
        XCTAssertEqual(DisplayUnit.milesPerHour.fromCanonical(1.4), 3.1317, accuracy: 0.0001)
    }

    /// Every unit must survive a round trip, because an input field uses one
    /// direction and the read-out beside it uses the other.
    func testEveryUnitRoundTrips() {
        let units: [DisplayUnit] = [.kilograms, .pounds, .metres, .centimetres, .inches,
                                    .inchesFromMetres, .kilometres, .miles, .celsius,
                                    .fahrenheit, .celsiusDifference, .fahrenheitDifference,
                                    .litres, .usFluidOunces, .millimolesPerLitre,
                                    .milligramsPerDecilitreGlucose,
                                    .milligramsPerDecilitreCholesterol,
                                    .metresPerSecond, .milesPerHour]
        for unit in units {
            for canonical in [-3.7, 0, 0.4, 37.0, 86.36, 220.5] {
                XCTAssertEqual(unit.toCanonical(unit.fromCanonical(canonical)), canonical,
                               accuracy: 1e-9,
                               "\(unit.abbreviation) does not round-trip at \(canonical)")
            }
        }
    }

    /// ⚠️ The offset trap. A skin-temperature *deviation* of −0.4 °C is a dip of
    /// 0.72 °F, not 31.3 °F.
    func testATemperatureDifferenceCarriesNoOffset() {
        XCTAssertEqual(DisplayUnit.fahrenheitDifference.fromCanonical(-0.4), -0.72, accuracy: 1e-9)
        XCTAssertEqual(DisplayUnit.fahrenheitDifference.fromCanonical(0), 0, accuracy: 1e-9)
        // And the absolute form is what would have got it wrong.
        XCTAssertEqual(DisplayUnit.fahrenheit.fromCanonical(0), 32, accuracy: 1e-9)
        XCTAssertNotEqual(MetricType.skinTemperatureDeviation.measurementQuantity,
                          MetricType.skinTemperature.measurementQuantity)
    }

    /// ⚠️ The molar-mass trap. Glucose and cholesterol are different molecules
    /// and their mmol/L → mg/dL factors differ by a bit over twofold.
    func testGlucoseAndCholesterolDoNotShareAFactor() {
        // 5.5 mmol/L glucose ≈ 99 mg/dL.
        XCTAssertEqual(DisplayUnit.milligramsPerDecilitreGlucose.fromCanonical(5.5),
                       99.09, accuracy: 0.01)
        // 5.5 mmol/L total cholesterol ≈ 213 mg/dL.
        XCTAssertEqual(DisplayUnit.milligramsPerDecilitreCholesterol.fromCanonical(5.5),
                       212.66, accuracy: 0.01)
        XCTAssertNotEqual(DisplayUnit.milligramsPerDecilitreGlucose,
                          DisplayUnit.milligramsPerDecilitreCholesterol)
    }

    /// A US lipid panel reads "Total 195". Typed into the sheet on a US phone it
    /// must land as roughly 5.0 mmol/L, not as 195.
    func testAUSLipidPanelLandsAsMillimoles() {
        guard let unit = MeasurementQuantity.cholesterol.unit(in: .usCustomary) else {
            return XCTFail("US cholesterol has no unit")
        }
        XCTAssertEqual(unit.abbreviation, "mg/dL")
        XCTAssertEqual(unit.toCanonical(195), 5.043, accuracy: 0.001)
    }

    /// A British reader's blood test is printed in mmol/L even though they weigh
    /// themselves in pounds. Offering them mg/dL is the wrong number.
    func testBritainKeepsClinicalUnitsMetric() {
        XCTAssertEqual(MeasurementQuantity.cholesterol.unit(in: .britishHybrid)?.abbreviation,
                       "mmol/L")
        XCTAssertEqual(MeasurementQuantity.bloodGlucose.unit(in: .britishHybrid)?.abbreviation,
                       "mmol/L")
        XCTAssertEqual(MeasurementQuantity.temperature.unit(in: .britishHybrid)?.abbreviation,
                       "°C")
        // …but the tape and the scales are imperial.
        XCTAssertEqual(MeasurementQuantity.tapeLength.unit(in: .britishHybrid)?.abbreviation, "in")
        XCTAssertEqual(MeasurementQuantity.bodyMass.unit(in: .britishHybrid)?.abbreviation, "lb")
    }

    // MARK: - The exhaustive mapping

    /// Every metric answers, and every metric that says "no conversion" has a
    /// unit label that really is the same in every country.
    func testEveryMetricDeclaresAQuantityConsistentWithItsUnitLabel() {
        // Unit labels that are identical worldwide. Anything else claiming
        // `.universal` is a mapping bug.
        let worldwide: Set<String> = ["bpm", "ms", "mL/kg·min", "years", "br/min", "%", "",
                                      "mmHg", "steps", "kcal", "min", "flights", "METs",
                                      "g", "mg", "mcg", "h", "dBA"]
        for metric in MetricType.allCases {
            let quantity = metric.measurementQuantity
            if quantity == .universal {
                XCTAssertTrue(worldwide.contains(metric.unit),
                              "\(metric) says .universal but its unit is \"\(metric.unit)\"")
                XCTAssertNil(metric.displayUnit(in: .usCustomary),
                             "\(metric) says .universal but offered a US unit")
            } else {
                XCTAssertFalse(worldwide.contains(metric.unit),
                               "\(metric) claims to convert but its unit \"\(metric.unit)\" is worldwide")
                XCTAssertNotNil(metric.displayUnit(in: .usCustomary))
                XCTAssertNotNil(metric.displayUnit(in: .metric))
            }
        }
    }

    /// In a metric system, every metric's chosen unit must be the one the value
    /// is actually stored in — otherwise the "no change for existing readers"
    /// claim in `MeasurementSystem.swift` is false.
    func testMetricSystemIsAlwaysTheCanonicalUnit() {
        for metric in MetricType.allCases {
            guard let unit = metric.displayUnit(in: .metric) else { continue }
            XCTAssertTrue(unit.isCanonical, "\(metric) rescales itself in the metric system")
            XCTAssertEqual(unit.abbreviation, metric.unit,
                           "\(metric) disagrees with MetricType.unit about its own stored unit")
        }
    }

    func testGroundingKindsDeclareTheirQuantity() {
        for kind in GroundingKind.allCases {
            switch kind {
            case .totalCholesterol, .hdlCholesterol:
                XCTAssertEqual(kind.measurementQuantity, .cholesterol)
            default:
                XCTAssertEqual(kind.measurementQuantity, .universal, "\(kind)")
            }
        }
    }

    // MARK: - The formatter seam

    func testMeasuredRestatesTheValueAndTheUnitTogether() {
        let (value, unit) = MetricValueFormatter.measured(82.0, .bodyMass, in: .usCustomary)
        XCTAssertEqual(value, 180.779, accuracy: 0.001)
        XCTAssertEqual(unit, "lb")
    }

    func testMeasuredLeavesUniversalMetricsAlone() {
        let (value, unit) = MetricValueFormatter.measured(62.0, .heartRate, in: .usCustomary)
        XCTAssertEqual(value, 62)
        XCTAssertEqual(unit, "bpm")
    }

    func testMeasuredStringConverts() {
        XCTAssertEqual(MetricValueFormatter.measuredString(86.36, .waistCircumference,
                                                           in: .usCustomary), "34.0 in")
        XCTAssertEqual(MetricValueFormatter.measuredString(37.0, .bodyTemperature,
                                                           in: .usCustomary), "98.6 °F")
        XCTAssertEqual(MetricValueFormatter.measuredString(2.0, .dietaryWater,
                                                           in: .usCustomary), "68 fl oz")
    }

    /// The metric path must be byte-identical to what shipped before, or this
    /// file has silently changed what the current reader sees.
    func testMetricSystemRendersExactlyWhatItAlreadyDid() {
        for (value, metric) in [(82.35, MetricType.bodyMass), (86.4, .waistCircumference),
                                (37.1, .bodyTemperature), (5.4, .bloodGlucose),
                                (62.4, .heartRate), (2.1, .dietaryWater)] {
            XCTAssertEqual(MetricValueFormatter.measuredString(value, metric, in: .metric),
                           MetricValueFormatter.detailedString(value, metric),
                           "\(metric) changed in the metric system")
        }
    }

    /// A CGM reading is not an integer. `3.4` and `3.9` are a hypo and a normal,
    /// and the formatter used to render both as "3".
    func testBloodGlucoseKeepsItsDecimal() {
        XCTAssertEqual(MetricValueFormatter.string(5.4, .bloodGlucose), "5.4")
        XCTAssertEqual(MetricValueFormatter.string(3.9, .bloodGlucose), "3.9")
    }
}
