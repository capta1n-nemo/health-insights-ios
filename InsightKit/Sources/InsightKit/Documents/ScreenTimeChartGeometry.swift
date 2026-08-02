import Foundation

/// A screenshot's chart region reduced to "is this pixel part of a drawn bar".
///
/// The whole point of this type is that it is **not** an image: turning pixels
/// into a boolean grid is the only part of reading a bar chart that needs
/// CoreGraphics, and everything interesting that happens afterwards is
/// arithmetic. So the conversion lives in the app target (`ScreenTimeChartReader`)
/// and every decision lives here, where it runs on Linux and has tests.
///
/// That split is the same one `add-chart` §5 asks for and for the same reason:
/// the app target has no test target, so a rule that lives there is verified by
/// eye — and this one would be verified by eye against a screenshot nobody has
/// on the machine that builds it.
public struct BarChartMask: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Row-major, `width * height` entries. True where a pixel is drawn ink
    /// rather than card background.
    public let ink: [Bool]

    public init(width: Int, height: Int, ink: [Bool]) {
        self.width = width
        self.height = height
        self.ink = ink
    }

    public func isInk(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, y >= 0, y < height else { return false }
        return ink[y * width + x]
    }

    /// How many columns have ink in this row.
    public func inkCount(row y: Int) -> Int {
        guard y >= 0, y < height else { return 0 }
        var count = 0
        for x in 0..<width where ink[y * width + x] { count += 1 }
        return count
    }
}

/// Measuring the seven bars of a Screen Time weekly chart.
///
/// ## What it is allowed to conclude
///
/// Only the **relative** heights. It never converts a pixel to a minute — the
/// exact weekly total comes from OCR and `ScreenTimeWeekBreakdown` distributes
/// it. So a systematic error in where the baseline sits cancels out entirely,
/// and the failure mode that remains is getting the *proportions* wrong, which
/// the reader is shown and confirms before anything is saved.
///
/// ## Returning nil is a real answer
///
/// Every step can fail to find what it is looking for, and each one returns nil
/// rather than a best guess. Seven bars is the shape of the thing; six clusters
/// means the chart was not found, or a bar was empty and merged with its
/// neighbour's gap, and a six-way split of a seven-day week is worse than no
/// split at all — the week total is recorded either way.
public enum ScreenTimeChartGeometry {

    public static let daysInWeek = 7

    /// A row this much of the width is a gridline or the average rule, not a bar.
    ///
    /// The weekly chart draws horizontal gridlines and a green dashed "avg"
    /// line straight across the plot. Left in, they make every column look like
    /// it has ink at that height and the tallest bar becomes the whole plot.
    static let fullWidthRowShare = 0.8

    /// A cluster narrower than this share of the average is noise — an axis
    /// tick, a stray antialiased pixel, part of a letter.
    static let minimumClusterShare = 0.35

    /// Relative heights of the seven bars, tallest-to-shortest preserved in
    /// left-to-right order, or nil where the chart could not be read.
    public static func barHeights(in mask: BarChartMask,
                                  expectedBars: Int = daysInWeek) -> [Double]? {
        guard mask.width > 0, mask.height > 0, expectedBars > 0 else { return nil }
        let cleaned = removingFullWidthRows(mask)
        guard let baseline = baselineRow(in: cleaned) else { return nil }
        let clusters = columnClusters(in: cleaned, above: baseline)
        guard clusters.count == expectedBars else { return nil }

        let heights = clusters.map { cluster in
            height(of: cluster, in: cleaned, baseline: baseline)
        }
        // All-zero would divide by nothing downstream; a week in which no bar
        // was measurable is a failure to read the chart, not a week of nothing.
        guard heights.contains(where: { $0 > 0 }) else { return nil }
        return heights
    }

    /// Blank out rows that run nearly the full width.
    ///
    /// Kept as a mask of the same size rather than cropping, so every row index
    /// still means what it meant to the caller.
    static func removingFullWidthRows(_ mask: BarChartMask) -> BarChartMask {
        guard mask.width > 0 else { return mask }
        var ink = mask.ink
        let limit = Int(Double(mask.width) * fullWidthRowShare)
        for y in 0..<mask.height where mask.inkCount(row: y) >= limit {
            for x in 0..<mask.width { ink[y * mask.width + x] = false }
        }
        return BarChartMask(width: mask.width, height: mask.height, ink: ink)
    }

    /// A row must carry this share of the busiest row's ink to be a candidate
    /// baseline. Below it lie the weekday glyphs and stray antialiasing.
    static let baselineCoverageShare = 0.5

    /// The row the bars stand on: the **lowest** substantially-inked row.
    ///
    /// The obvious version — "the row with the most ink" — is wrong, and a test
    /// caught it. The dashed green average rule crosses the plot at the height
    /// of a *tall* bar, so its row carries its own dashes plus the three bars it
    /// crosses, which can out-cover the baseline's seven narrow bars. Picking it
    /// makes every cluster a dash and the read fails.
    ///
    /// Every bar stands on the axis, so the baseline is the lowest row where
    /// they are all present; nothing on this chart is drawn below it except the
    /// weekday letters, which are seven small glyphs and fall under the share.
    static func baselineRow(in mask: BarChartMask) -> Int? {
        var maximum = 0
        for y in 0..<mask.height { maximum = max(maximum, mask.inkCount(row: y)) }
        guard maximum > 0 else { return nil }
        let floor = Double(maximum) * baselineCoverageShare
        for y in stride(from: mask.height - 1, through: 0, by: -1)
        where Double(mask.inkCount(row: y)) >= floor {
            return y
        }
        return nil
    }

    /// Contiguous runs of columns that have ink **at the baseline itself**.
    ///
    /// Not "anywhere above the baseline", which is the obvious version and is
    /// wrong: the chart draws a dashed green average rule across the plot, and a
    /// dash floating in the gap between two bars would join them into one
    /// cluster. Every bar stands on the axis by definition, and nothing else on
    /// this chart does.
    static func columnClusters(in mask: BarChartMask, above baseline: Int) -> [Range<Int>] {
        var occupied = [Bool](repeating: false, count: mask.width)
        for x in 0..<mask.width {
            occupied[x] = mask.isInk(x: x, y: baseline)
        }
        var runs: [Range<Int>] = []
        var start: Int?
        for x in 0..<mask.width {
            if occupied[x], start == nil { start = x }
            if !occupied[x], let from = start { runs.append(from..<x); start = nil }
        }
        if let from = start { runs.append(from..<mask.width) }
        guard !runs.isEmpty else { return [] }

        // Drop slivers, measured against the average run rather than an absolute
        // pixel count, so it holds at any screenshot scale.
        let average = Double(runs.reduce(0) { $0 + $1.count }) / Double(runs.count)
        return runs.filter { Double($0.count) >= average * minimumClusterShare }
    }

    /// A bar's height in pixels: the longest **unbroken** run of ink upward from
    /// the baseline within its cluster.
    ///
    /// Two decisions, both load-bearing:
    ///
    /// - **Unbroken**, not "topmost ink in the column". A bar is a solid block,
    ///   while the dashed average rule and the horizontal gridlines are detached
    ///   marks floating above it — and taking the topmost ink would measure a
    ///   short bar as reaching whatever line happened to cross its column. This
    ///   is the same reasoning as the cluster rule above.
    /// - **The tallest column** in the cluster rather than the mean, because a
    ///   bar is a rectangle and the mean is dragged down by the antialiased
    ///   pixels at each edge.
    static func height(of cluster: Range<Int>, in mask: BarChartMask,
                       baseline: Int) -> Double {
        var tallest = 0
        for x in cluster {
            var run = 0
            var y = baseline
            while y >= 0, mask.isInk(x: x, y: y) {
                run += 1
                y -= 1
            }
            tallest = max(tallest, run)
        }
        return Double(tallest)
    }
}
