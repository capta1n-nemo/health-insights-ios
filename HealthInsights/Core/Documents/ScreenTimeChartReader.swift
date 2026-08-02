import Foundation
import InsightKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// Turns a Screen Time weekly screenshot into the seven relative bar heights
/// that `ScreenTimeWeekBreakdown` splits the week's exact total across.
///
/// ## Everything decidable lives elsewhere
///
/// This type does one thing that genuinely needs CoreGraphics — read pixels —
/// and hands a `BarChartMask` to `ScreenTimeChartGeometry`, which is in
/// InsightKit with tests. That split matters more here than usual: the app
/// target has no test target, so anything left in this file is verified by eye
/// against a screenshot that does not exist on the machine that builds it.
///
/// ## Finding the chart without knowing where it is
///
/// The bars are the only large blocks of **saturated** colour on the screen —
/// blue, teal and orange segments. Headings, the app list and the weekday
/// letters are all grey or black, which is to say unsaturated, and the one
/// saturated thing that isn't a bar ("Show This Week" in link blue) is a thin
/// line of text rather than a band of rows.
///
/// So: find the rows carrying saturated pixels, take the tallest contiguous band
/// of them, and treat everything in that band that differs from the card
/// background as ink. A bar whose upper segments are grey — the reader's Monday
/// is almost entirely grey with an orange sliver at its foot — is still measured
/// in full, because the band is found from the sliver and the ink test inside it
/// is "not background" rather than "saturated".
enum ScreenTimeChartReader {

    /// Minimum saturation for a pixel to count as chart colour.
    private static let saturationFloor = 0.30
    /// A row needs this many saturated pixels to be part of the chart band —
    /// enough to rule out a line of link-coloured text.
    private static let saturatedRowFloor = 6
    /// How far a pixel must sit from the background to count as ink, as a
    /// fraction of the full 0–1 RGB cube diagonal.
    private static let inkDistance = 0.12

    /// Seven relative bar heights, or nil if the chart could not be read.
    ///
    /// Nil is a real answer and the caller must treat it as one: the week is
    /// still recorded from its exact printed total, just without a per-day
    /// split. Guessing a split from a chart that was not found is the one thing
    /// this must never do.
    static func barHeights(in image: PlatformImage) -> [Double]? {
        #if canImport(UIKit)
        guard let pixels = Pixels(image: image) else { return nil }
        guard let band = chartBand(in: pixels) else { return nil }
        let mask = inkMask(in: pixels, rows: band)
        return ScreenTimeChartGeometry.barHeights(in: mask)
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)

    /// The image decoded into straight RGBA8, whatever it arrived as.
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init?(image: UIImage) {
            guard let cg = image.cgImage else { return nil }
            let width = cg.width
            let height = cg.height
            guard width > 0, height > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &bytes, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.width = width
            self.height = height
            self.bytes = bytes
        }

        func rgb(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
            let index = (y * width + x) * 4
            return (Double(bytes[index]) / 255,
                    Double(bytes[index + 1]) / 255,
                    Double(bytes[index + 2]) / 255)
        }

        /// Saturation alone — the value component is irrelevant here, and using
        /// it would drop the darker end of a blue bar.
        func saturation(x: Int, y: Int) -> Double {
            let (r, g, b) = rgb(x: x, y: y)
            let high = max(r, g, b)
            let low = min(r, g, b)
            guard high > 0 else { return 0 }
            return (high - low) / high
        }
    }

    /// The rows the plot occupies: the tallest run of rows carrying enough
    /// saturated pixels to be bars rather than a line of coloured text.
    private static func chartBand(in pixels: Pixels) -> Range<Int>? {
        var saturatedRow = [Bool](repeating: false, count: pixels.height)
        for y in 0..<pixels.height {
            var count = 0
            for x in 0..<pixels.width where pixels.saturation(x: x, y: y) >= saturationFloor {
                count += 1
                if count >= saturatedRowFloor { break }
            }
            saturatedRow[y] = count >= saturatedRowFloor
        }

        var best: Range<Int>?
        var start: Int?
        for y in 0..<pixels.height {
            if saturatedRow[y], start == nil { start = y }
            if !saturatedRow[y], let from = start {
                let run = from..<y
                if run.count > (best?.count ?? 0) { best = run }
                start = nil
            }
        }
        if let from = start {
            let run = from..<pixels.height
            if run.count > (best?.count ?? 0) { best = run }
        }
        // A band only a few rows tall is a coloured word, not a chart.
        guard let best, best.count >= 12 else { return nil }
        return best
    }

    /// Everything in the band that is not the card background.
    ///
    /// The background is taken as the **most common** colour in the band, which
    /// on this screen is the card behind the bars — and works unchanged in dark
    /// mode, where it is near-black rather than near-white. Quantised to 5 bits
    /// per channel so antialiasing does not split one background into hundreds
    /// of nearly-identical buckets.
    private static func inkMask(in pixels: Pixels, rows: Range<Int>) -> BarChartMask {
        var histogram: [Int: Int] = [:]
        for y in rows {
            for x in 0..<pixels.width {
                let (r, g, b) = pixels.rgb(x: x, y: y)
                let key = (Int(r * 31) << 10) | (Int(g * 31) << 5) | Int(b * 31)
                histogram[key, default: 0] += 1
            }
        }
        let backgroundKey = histogram.max { $0.value < $1.value }?.key ?? 0
        let background = (r: Double((backgroundKey >> 10) & 31) / 31,
                          g: Double((backgroundKey >> 5) & 31) / 31,
                          b: Double(backgroundKey & 31) / 31)

        var ink = [Bool](repeating: false, count: pixels.width * rows.count)
        for (row, y) in rows.enumerated() {
            for x in 0..<pixels.width {
                let (r, g, b) = pixels.rgb(x: x, y: y)
                let distance = ((r - background.r) * (r - background.r)
                                + (g - background.g) * (g - background.g)
                                + (b - background.b) * (b - background.b)).squareRoot()
                ink[row * pixels.width + x] = distance > inkDistance
            }
        }
        return BarChartMask(width: pixels.width, height: rows.count, ink: ink)
    }

    #endif
}

/// When a picked image was actually taken.
///
/// **The whole retrospective import rests on this.** Every relative phrase on
/// the Screen Time screen — "Today", "Last Week" — is relative to the moment of
/// capture, so a screenshot from three weeks ago read against `Date()` files
/// itself into the week it was imported in. Read from the image's own metadata
/// rather than PhotoKit, so it needs no photo-library permission: the picker
/// already handed over the bytes.
enum ImageCaptureDate {

    /// EXIF/TIFF capture date, or nil when the image carries none.
    ///
    /// Nil is not "today". The caller has to say it could not tell, because
    /// silently substituting today is the exact bug this exists to fix.
    static func read(from data: Data) -> Date? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else { return nil }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = formatter.date(from: original) {
            return date
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let stamp = tiff[kCGImagePropertyTIFFDateTime] as? String,
           let date = formatter.date(from: stamp) {
            return date
        }
        return nil
        #else
        return nil
        #endif
    }

    /// EXIF's own format. Fixed locale and POSIX calendar — this string is a
    /// wire format, not something to render.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
