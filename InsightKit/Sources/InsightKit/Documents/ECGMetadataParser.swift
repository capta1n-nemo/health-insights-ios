import Foundation

/// **Reads the metadata printed around an ECG trace. Never the trace.**
///
/// Backlog `I7`. Pure and Linux-tested, like every other parser in this folder,
/// and for a sharper reason than usual: the one thing this must not learn to do
/// is look at the waveform, and a type that only ever receives a `String` of
/// recognised text *cannot*. The restriction is in the signature.
///
/// What it reads is the text an ECG document prints beside the trace — Apple
/// Health's PDF export, a clinic's twelve-lead printout, a photograph of either:
///
/// - when it was recorded;
/// - the average rate the device printed;
/// - how many seconds of trace;
/// - what machine made it;
/// - how many leads;
/// - and the classification the **device or clinician** printed, quoted with an
///   attribution attached (`ECGFindingProvenance`).
///
/// ⚠️ **The classification is transcribed, not decided.** `finding(in:)` matches
/// a known phrase *that is already on the page* and refuses anything it did not
/// find there — it cannot output a classification the document does not print,
/// which is the difference between transcription and diagnosis.
public enum ECGMetadataParser {

    public struct Result: Sendable, Equatable {
        public let recordedAt: Date?
        public let averageHeartRate: Int?
        public let durationSeconds: Double?
        public let device: String?
        public let leads: ECGLeadConfiguration
        public let printedFinding: String?
        public let findingProvenance: ECGFindingProvenance?
        public let evidence: ECGTranscriptionEvidence

        public init(recordedAt: Date?, averageHeartRate: Int?, durationSeconds: Double?,
                    device: String?, leads: ECGLeadConfiguration,
                    printedFinding: String?, findingProvenance: ECGFindingProvenance?,
                    evidence: ECGTranscriptionEvidence) {
            self.recordedAt = recordedAt
            self.averageHeartRate = averageHeartRate
            self.durationSeconds = durationSeconds
            self.device = device
            self.leads = leads
            self.printedFinding = printedFinding
            self.findingProvenance = findingProvenance
            self.evidence = evidence
        }
    }

    public static func parse(_ text: String) -> Result {
        var matchedLines: [String] = []
        var checks: [LabValueCheck] = []
        var absent: [ECGField] = []

        let lines = text.split(separator: "\n").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        // ---- Recorded at.
        let recordedAt = recordedDate(in: text, lines: lines, matched: &matchedLines)
        if recordedAt == nil { absent.append(.recordedAt) }

        // ---- Average heart rate.
        //
        // ⚠️ Range-checked the same way a lab value is, and for the same reason:
        // "62 BPM" OCR'd as "620 BPM" is a misread, not a tachycardia, and a
        // number that cannot have been printed must not be stored as though it
        // were. The bounds are the widest a device prints, not a clinical
        // opinion about anybody's rate.
        var averageHeartRate: Int?
        if let (rate, line) = firstLabelledInteger(in: lines, labels: [
            "average heart rate", "avg heart rate", "heart rate", "avg hr", "hr"
        ]) {
            if (20...300).contains(rate) {
                averageHeartRate = rate
                matchedLines.append(line)
                checks.append(.plausibleMagnitude)
            } else {
                checks.append(.implausibleMagnitude)
            }
        } else {
            absent.append(.averageHeartRate)
        }

        // ---- Duration.
        var durationSeconds: Double?
        if let (seconds, line) = duration(in: lines) {
            durationSeconds = seconds
            matchedLines.append(line)
        } else {
            absent.append(.duration)
        }

        // ---- Device.
        let device = deviceName(in: lines, matched: &matchedLines)
        if device == nil { absent.append(.device) }

        // ---- Leads.
        let leads = leadConfiguration(in: text)
        if leads == .unstated { absent.append(.leads) }

        // ---- The printed classification, quoted.
        let found = finding(in: lines)
        if found == nil { absent.append(.finding) }
        if !matchedLines.isEmpty { checks.append(.corroboratedInSourceText) }

        let evidence = ECGTranscriptionEvidence(matchedLines: matchedLines,
                                                checks: checks,
                                                absentFields: absent)
        return Result(recordedAt: recordedAt,
                      averageHeartRate: averageHeartRate,
                      durationSeconds: durationSeconds,
                      device: device,
                      leads: leads,
                      printedFinding: found?.text,
                      findingProvenance: found?.provenance,
                      evidence: evidence)
    }

    // MARK: - Fields

    static func recordedDate(in text: String, lines: [String],
                             matched: inout [String]) -> Date? {
        let markers = ["recorded", "recording date", "date of recording",
                       "acquired", "date/time", "date and time", "taken"]
        for line in lines {
            let lower = line.lowercased()
            guard markers.contains(where: { lower.contains($0) }) else { continue }
            if let date = dateAndTime(in: line) {
                matched.append(line)
                return date
            }
        }
        // A document that prints a bare date with no label at all — common on a
        // photographed printout where the header cropped. Taken only when there
        // is exactly one date on the page, so a footer's "printed on" cannot be
        // confused for the recording.
        var dates: [Date] = []
        for line in lines {
            if let date = dateAndTime(in: line) { dates.append(date) }
        }
        if dates.count == 1 { return dates[0] }
        return nil
    }

    static func dateAndTime(in s: String) -> Date? {
        // Apple Health's PDF prints "24 July 2026 at 14:05" or similar; a clinic
        // machine prints "24/07/2026 14:05". Both are handled, and a date with
        // no time is accepted at midnight — which is why `recordedAtIsExact`
        // exists on the record rather than a nil check on the time.
        let formats = ["d MMMM yyyy 'at' HH:mm", "d MMM yyyy 'at' HH:mm",
                       "dd/MM/yyyy HH:mm", "yyyy-MM-dd HH:mm",
                       "d MMMM yyyy", "d MMM yyyy", "dd/MM/yyyy", "yyyy-MM-dd"]
        let patterns = [
            #"[0-9]{1,2}\s+[A-Za-z]{3,9}\s+[0-9]{4}\s+at\s+[0-9]{1,2}:[0-9]{2}"#,
            #"[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}\s+[0-9]{1,2}:[0-9]{2}"#,
            #"[0-9]{4}-[0-9]{2}-[0-9]{2}\s+[0-9]{1,2}:[0-9]{2}"#,
            #"[0-9]{1,2}\s+[A-Za-z]{3,9}\s+[0-9]{4}"#,
            #"[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}"#,
            #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#
        ]
        for pattern in patterns {
            guard let found = s.range(of: pattern, options: .regularExpression) else { continue }
            let raw = String(s[found]).replacingOccurrences(of: "  ", with: " ")
            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_GB")
                formatter.timeZone = TimeZone.current
                formatter.dateFormat = format
                if let date = formatter.date(from: raw) { return date }
            }
        }
        return nil
    }

    static func firstLabelledInteger(in lines: [String],
                                     labels: [String]) -> (Int, String)? {
        // Longest label first: "average heart rate" must not be consumed by "hr".
        for label in labels.sorted(by: { $0.count > $1.count }) {
            for line in lines {
                let lower = line.lowercased()
                guard let labelRange = lower.range(of: label) else { continue }
                let after = String(line[labelRange.upperBound...])
                guard let token = LabReportParser.numberTokens(in: after).first else { continue }
                return (Int(token.value.rounded()), line)
            }
        }
        return nil
    }

    static func duration(in lines: [String]) -> (Double, String)? {
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("duration") || lower.contains("length") else { continue }
            guard let token = LabReportParser.numberTokens(in: line).first else { continue }
            // "30 sec", "0:30", "30s" — a minutes:seconds form has two tokens.
            let tokens = LabReportParser.numberTokens(in: line)
            if lower.contains(":") && tokens.count >= 2 {
                return (tokens[0].value * 60 + tokens[1].value, line)
            }
            if lower.contains("min") && !lower.contains("sec") {
                return (token.value * 60, line)
            }
            return (token.value, line)
        }
        return nil
    }

    static func deviceName(in lines: [String], matched: inout [String]) -> String? {
        let markers = ["device", "recorded on", "recorded with", "source",
                       "manufacturer", "model"]
        for line in lines {
            let lower = line.lowercased()
            guard let marker = markers.first(where: { lower.contains($0) }) else { continue }
            guard let range = lower.range(of: marker) else { continue }
            var value = String(line[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " :\t-—"))
            guard !value.isEmpty, value.count <= 60 else { continue }
            // A label line with the value on the next line is common; refuse
            // rather than pick up whatever follows, because the wrong device
            // name is worse than none.
            if value.count < 2 { continue }
            value = value.trimmingCharacters(in: .whitespaces)
            matched.append(line)
            return value
        }
        // Apple's export names the watch without any label at all.
        for line in lines where line.lowercased().contains("apple watch") {
            matched.append(line)
            return line.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func leadConfiguration(in text: String) -> ECGLeadConfiguration {
        let lower = text.lowercased()
        if lower.contains("12 lead") || lower.contains("12-lead") { return .twelveLead }
        if lower.contains("6 lead") || lower.contains("6-lead") { return .sixLead }
        if lower.contains("single lead") || lower.contains("1 lead")
            || lower.contains("lead i") { return .singleLead }
        return .unstated
    }

    /// The classification the **document** prints, quoted with an attribution.
    ///
    /// ⚠️ Every phrase here is matched against text that is already on the page,
    /// and the returned string is the page's own line — not the phrase that
    /// matched it. So the app cannot emit a classification the document does not
    /// contain, which is the whole difference between transcribing a finding and
    /// making one.
    ///
    /// The list is deliberately of *device statements*: these are the words an
    /// Apple Watch or an automated machine prints. Extending it is extending
    /// what can be recognised as a quotation, never what can be concluded.
    static let devicePhrases = [
        "sinus rhythm", "atrial fibrillation", "high heart rate", "low heart rate",
        "inconclusive", "poor recording", "unclassified", "normal ecg",
        "abnormal ecg", "borderline ecg", "otherwise normal ecg"
    ]

    static func finding(in lines: [String]) -> (text: String, provenance: ECGFindingProvenance)? {
        for line in lines {
            let lower = line.lowercased()
            guard devicePhrases.contains(where: { lower.contains($0) }) else { continue }
            // Skip a legend or a key that lists every possible result.
            let hits = devicePhrases.filter { lower.contains($0) }.count
            if hits > 2 { continue }
            return (line.trimmingCharacters(in: .whitespaces), .recordingDevice)
        }
        return nil
    }
}
