import XCTest
@testable import InsightKit

/// **"What even is HRV… am i about to die?"** — the reader, 2026-08-05, asking
/// for three things wherever a term appears: what it is, what *mine* means, and
/// so what.
final class MetricExplainerTests: XCTestCase {

    /// Every term the reader named by hand must be covered. This is the list
    /// from their own message, not a sample of it.
    func testEveryTermTheReaderNamedIsExplained() {
        for metric in [MetricType.heartRateVariabilityRMSSD, .heartRateVariabilitySDNN,
                       .vo2Max, .oxygenSaturation, .sleepEfficiency,
                       .sleepLatencyMinutes, .vascularAge] {
            XCTAssertNotNil(MetricExplainer.explanation(for: metric),
                            "\(metric) was named by the reader and has no explanation")
        }
    }

    /// An explanation that exists must actually say something in both halves.
    func testNoExplanationIsHalfWritten() {
        for metric in MetricType.allCases {
            guard let e = MetricExplainer.explanation(for: metric) else { continue }
            XCTAssertGreaterThan(e.whatItIs.count, 40, "\(metric)'s definition is a stub")
            XCTAssertGreaterThan(e.soWhat.count, 40, "\(metric)'s so-what is a stub")
        }
    }

    /// **No Markdown in the prose, because nothing renders it.**
    ///
    /// Found by looking at the simulator, not by a test: the HRV explanation
    /// carried `**…**` around its most important sentence and SwiftUI's `Text`
    /// printed the asterisks verbatim on the card. Every assertion here passed
    /// while the screen was wrong — a `String` is not a `LocalizedStringKey`,
    /// and this app's prose is written in doc comments where `**` is normal, so
    /// the habit leaks.
    func testNoExplanationCarriesMarkdown() {
        for metric in MetricType.allCases {
            guard let e = MetricExplainer.explanation(for: metric) else { continue }
            for text in [e.whatItIs, e.soWhat] {
                // Single asterisks too — a `**`-only check let `*shape*` through
                // in the energy explainer minutes after this test was written.
                XCTAssertFalse(text.contains("*"), "\(metric) renders literal asterisks: \(text)")
                XCTAssertFalse(text.contains("_"), "\(metric) renders a literal underscore: \(text)")
                XCTAssertFalse(text.contains("`"), "\(metric) renders a literal backtick: \(text)")
            }
        }
    }

    /// **The definition must not contain the term it defines.** "Heart rate
    /// variability is the variability of your heart rate" is the failure mode
    /// of every glossary ever written, and it is exactly what the reader was
    /// complaining about.
    func testADefinitionNeverRestatesItsOwnName() {
        for metric in MetricType.allCases {
            guard let e = MetricExplainer.explanation(for: metric) else { continue }
            let name = metric.displayName.lowercased()
            XCTAssertFalse(e.whatItIs.lowercased().hasPrefix(name),
                           "\(metric) defines itself with its own name: \(e.whatItIs)")
        }
    }

    // MARK: - "What mine means" comes from the reader, not a table

    func testAPersonalReadingPlacesTheValueInTheReadersOwnRange() throws {
        let history = (0..<40).map { 40.0 + Double($0 % 20) }   // 40…59
        let text = try XCTUnwrap(
            MetricExplainer.yours(.heartRateVariabilityRMSSD, value: 49, history: history))
        XCTAssertTrue(text.contains("your own usual"), text)
        XCTAssertTrue(text.contains("49"), text)
    }

    func testAnExtremeValueIsNamedAsExtreme() throws {
        let history = (0..<40).map { 40.0 + Double($0 % 20) }
        let low = try XCTUnwrap(MetricExplainer.yours(.restingHeartRate, value: 20, history: history))
        let high = try XCTUnwrap(MetricExplainer.yours(.restingHeartRate, value: 90, history: history))
        XCTAssertTrue(low.contains("lower than almost any day"), low)
        XCTAssertTrue(high.contains("higher than almost any day"), high)
    }

    /// **Silence rather than a fiction.** With a handful of readings a p10–p90
    /// is two points wide, and "your usual" would be inventing a range.
    func testTooLittleHistorySaysNothingAtAll() {
        XCTAssertNil(MetricExplainer.yours(.restingHeartRate, value: 60, history: [58, 60, 62]))
        XCTAssertNil(MetricExplainer.yours(.restingHeartRate, value: 60, history: []))
    }

    /// A flat history has no spread to place a value inside, and dividing the
    /// reader's day into a range of zero width would say something false.
    func testAFlatHistorySaysNothing() {
        XCTAssertNil(MetricExplainer.yours(.restingHeartRate, value: 60,
                                           history: Array(repeating: 60.0, count: 30)))
    }

    /// The personal sentence must never quote a population figure — the whole
    /// point is that it is the reader's own record. Asserted by the absence of
    /// the words a normative claim needs.
    func testThePersonalReadingMakesNoPopulationClaim() throws {
        let history = (0..<40).map { 40.0 + Double($0 % 20) }
        let text = try XCTUnwrap(
            MetricExplainer.yours(.heartRateVariabilityRMSSD, value: 49, history: history))
        for word in ["normal", "average person", "healthy range", "should be", "typical adult"] {
            XCTAssertFalse(text.lowercased().contains(word),
                           "the personal reading made a population claim (\"\(word)\"): \(text)")
        }
    }

    /// The units come from the metric, so a value never appears bare.
    func testTheUnitIsCarried() throws {
        let history = (0..<40).map { 40.0 + Double($0 % 20) }
        let text = try XCTUnwrap(MetricExplainer.yours(.restingHeartRate, value: 49, history: history))
        XCTAssertTrue(text.contains("bpm"), text)
    }

    /// Self-explanatory metrics are deliberately silent, and that has to stay a
    /// decision rather than drift into "we never got round to it".
    func testTheSelfExplanatoryAreDeliberatelySilent() {
        for metric in [MetricType.stepCount, .bodyMass, .dietaryWater, .sleepDurationHours] {
            XCTAssertNil(MetricExplainer.explanation(for: metric),
                         "\(metric) gained an explanation nobody needs")
        }
    }
}
