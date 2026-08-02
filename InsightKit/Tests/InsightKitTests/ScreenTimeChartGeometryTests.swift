import XCTest
@testable import InsightKit

/// Measuring the seven bars of a weekly Screen Time chart.
///
/// Synthetic masks rather than real screenshots: the conversion from pixels to
/// ink lives in the app target and cannot run here, and what actually needs
/// pinning is the arithmetic on the other side of it — which bar is which, where
/// the baseline is, and that a chart it cannot read returns nothing rather than
/// a plausible-looking six-way split.
final class ScreenTimeChartGeometryTests: XCTestCase {

    /// Build a mask from bar heights, laid out like the real chart: evenly
    /// spaced columns of equal width standing on a common baseline, with a
    /// margin below for the weekday letters.
    private func mask(bars: [Int], barWidth: Int = 4, gap: Int = 3,
                      height: Int = 40, belowAxis: Int = 6) -> BarChartMask {
        let width = bars.count * (barWidth + gap) + gap
        var ink = [Bool](repeating: false, count: width * height)
        let baseline = height - belowAxis - 1
        for (index, bar) in bars.enumerated() {
            guard bar > 0 else { continue }
            let x0 = gap + index * (barWidth + gap)
            for x in x0..<(x0 + barWidth) {
                for y in (baseline - bar + 1)...baseline where y >= 0 {
                    ink[y * width + x] = true
                }
            }
        }
        return BarChartMask(width: width, height: height, ink: ink)
    }

    // MARK: - The measurement

    func testSevenBarsAreMeasuredInOrder() throws {
        let heights = try XCTUnwrap(
            ScreenTimeChartGeometry.barHeights(in: mask(bars: [3, 6, 5, 8, 10, 11, 15])))
        XCTAssertEqual(heights, [3, 6, 5, 8, 10, 11, 15])
    }

    /// Only the ratios are ever used, so a chart drawn at twice the scale must
    /// produce proportionally identical numbers.
    func testHeightsScaleWithTheScreenshot() throws {
        let small = try XCTUnwrap(
            ScreenTimeChartGeometry.barHeights(in: mask(bars: [2, 4, 6, 8, 10, 12, 14])))
        let large = try XCTUnwrap(ScreenTimeChartGeometry.barHeights(
            in: mask(bars: [4, 8, 12, 16, 20, 24, 28], barWidth: 8, gap: 6, height: 80,
                     belowAxis: 12)))
        let smallRatio = small.map { $0 / small.max()! }
        let largeRatio = large.map { $0 / large.max()! }
        for (a, b) in zip(smallRatio, largeRatio) {
            XCTAssertEqual(a, b, accuracy: 0.0001)
        }
    }

    // MARK: - What would otherwise wreck it

    /// **Gridlines and the green "avg" rule span the whole plot.** Left in,
    /// every column has ink at that height and every bar measures as the full
    /// height of the chart.
    func testAFullWidthGridlineIsIgnored() throws {
        var base = mask(bars: [3, 6, 5, 8, 10, 11, 15])
        var ink = base.ink
        let gridRow = 8
        for x in 0..<base.width { ink[gridRow * base.width + x] = true }
        base = BarChartMask(width: base.width, height: base.height, ink: ink)

        let heights = try XCTUnwrap(ScreenTimeChartGeometry.barHeights(in: base))
        XCTAssertEqual(heights, [3, 6, 5, 8, 10, 11, 15],
                       "the gridline must not lift every bar to the top of the plot")
    }

    /// **The green "avg" rule is dashed**, so it covers only about half the
    /// width and survives the full-width filter that removes the solid
    /// gridlines. It must not lift a short bar to its own height, and its
    /// dashes must not bridge the gap between two bars into one cluster.
    func testTheDashedAverageRuleIsNotPartOfAnyBar() throws {
        var base = mask(bars: [3, 6, 5, 8, 10, 11, 15])
        var ink = base.ink
        let baseline = base.height - 6 - 1
        let ruleRow = baseline - 9                    // above the four shortest bars
        // Dashes: two on, two off, right across the plot.
        for x in stride(from: 0, to: base.width, by: 4) {
            ink[ruleRow * base.width + x] = true
            if x + 1 < base.width { ink[ruleRow * base.width + x + 1] = true }
        }
        base = BarChartMask(width: base.width, height: base.height, ink: ink)

        let heights = try XCTUnwrap(ScreenTimeChartGeometry.barHeights(in: base))
        XCTAssertEqual(heights, [3, 6, 5, 8, 10, 11, 15],
                       "a detached dash above a short bar is not part of it")
    }

    /// The weekday letters sit below the axis. Scanning upward from the baseline
    /// is what keeps them out of the measurement.
    func testGlyphsBelowTheAxisDoNotCount() throws {
        var base = mask(bars: [4, 4, 4, 4, 4, 4, 4])
        var ink = base.ink
        let labelRow = base.height - 3
        for index in 0..<7 {
            let x = 3 + index * 7 + 1
            ink[labelRow * base.width + x] = true
        }
        base = BarChartMask(width: base.width, height: base.height, ink: ink)

        let heights = try XCTUnwrap(ScreenTimeChartGeometry.barHeights(in: base))
        XCTAssertEqual(heights, Array(repeating: 4.0, count: 7))
    }

    // MARK: - Refusing to guess

    /// Six clusters is not a week. A six-way split of seven days is worse than
    /// no split — the week's total is recorded either way.
    func testTheWrongNumberOfBarsIsNotReadAtAll() {
        XCTAssertNil(ScreenTimeChartGeometry.barHeights(in: mask(bars: [3, 6, 5, 8, 10, 11])))
        XCTAssertNil(ScreenTimeChartGeometry.barHeights(in: mask(bars: [1, 2, 3, 4, 5, 6, 7, 8])))
    }

    func testAnEmptyMaskReadsNothing() {
        XCTAssertNil(ScreenTimeChartGeometry.barHeights(
            in: BarChartMask(width: 0, height: 0, ink: [])))
        XCTAssertNil(ScreenTimeChartGeometry.barHeights(
            in: BarChartMask(width: 10, height: 10,
                             ink: [Bool](repeating: false, count: 100))))
    }

    /// A day with no screen time draws no bar, so the chart has six clusters and
    /// cannot be read. **Recorded here as the known limit it is**: the week
    /// still imports with its exact total, and the reader can screenshot that
    /// day to get it exactly. Inferring which of the seven was missing from the
    /// gaps is guessing at the one number nobody can see.
    func testAZeroDayCollapsesToSixClustersAndIsRefused() {
        XCTAssertNil(ScreenTimeChartGeometry.barHeights(in: mask(bars: [3, 0, 5, 8, 10, 11, 15])))
    }

    // MARK: - The pieces

    func testTheBaselineIsTheWidestRow() throws {
        let base = mask(bars: [3, 6, 5, 8, 10, 11, 15])
        let baseline = try XCTUnwrap(ScreenTimeChartGeometry.baselineRow(in: base))
        XCTAssertEqual(baseline, base.height - 6 - 1)
    }

    func testClustersFindOneRunPerBar() {
        let base = mask(bars: [3, 6, 5, 8, 10, 11, 15])
        let baseline = ScreenTimeChartGeometry.baselineRow(in: base)!
        XCTAssertEqual(ScreenTimeChartGeometry.columnClusters(in: base, above: baseline).count, 7)
    }

    /// A one-pixel sliver of antialiasing is not a bar.
    func testSliversAreDropped() {
        var base = mask(bars: [4, 4, 4, 4, 4, 4, 4])
        var ink = base.ink
        let baseline = base.height - 6 - 1
        ink[baseline * base.width + 0] = true      // a stray pixel at the left edge
        base = BarChartMask(width: base.width, height: base.height, ink: ink)
        let clusters = ScreenTimeChartGeometry.columnClusters(in: base, above: baseline)
        XCTAssertEqual(clusters.count, 7)
    }
}
