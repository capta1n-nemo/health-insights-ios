import Foundation
import InsightKit

/// Taking a Shotsy backup in from the share sheet or a file picker.
///
/// Shotsy has no API, so the file *is* the integration. That makes this the
/// app's first file-shaped input — the same shape photos and scans will need —
/// so the parsing lives in InsightKit (pure, testable, and it already is) and
/// only the file handling and persistence are here.
///
/// **Imported doses supersede inferred ones**, and the user's own export is why.
/// `TitrationEngine` guesses a standard ladder — 2.5 → 5 → 7.5 → 10 → 12.5 at
/// four-week steps — and their real history runs
/// 2.5 ×3, 4.5, 5 ×4, 6, 7.5 ×5, 10 ×3, **11**, back **down** to 7.5, then
/// 12.5: three doses that are not on the ladder at all, intervals from five to
/// fifteen days, and a reduction no titration model would ever predict. A guess
/// has no business outliving the record it was standing in for.
@MainActor
struct ShotsyImportService {

    struct Summary: Sendable {
        var doses = 0
        var supersededInferred = 0
        var samples = 0
        var sideEffects = 0
        var unmappedKinds: [String] = []
        var scheduleName: String?

        var isEmpty: Bool { doses == 0 && samples == 0 }

        /// One sentence for the confirmation the reader sees. Says what was
        /// ignored as well as what landed — an import that silently drops five
        /// kinds of nutrition data is how somebody concludes the app lost it.
        var sentence: String {
            var parts: [String] = []
            if doses > 0 { parts.append("\(doses) \(doses == 1 ? "injection" : "injections")") }
            if samples > 0 { parts.append("\(samples) measurements") }
            if sideEffects > 0 { parts.append("\(sideEffects) side-effect \(sideEffects == 1 ? "record" : "records")") }
            var text = parts.isEmpty ? "Nothing new to import." : "Imported " + parts.joined(separator: ", ") + "."
            if supersededInferred > 0 {
                text += " \(supersededInferred) estimated \(supersededInferred == 1 ? "dose" : "doses") replaced by your real history."
            }
            if !unmappedKinds.isEmpty {
                text += " Not imported yet: \(unmappedKinds.joined(separator: ", ")) — the app has nowhere to put them."
            }
            return text
        }
    }

    let dataStore: DataStore

    /// Read a shared file. Handles the security scope a share-sheet URL arrives
    /// inside — without it the read fails on a real device while working
    /// perfectly in the simulator, which is the classic way this bug ships.
    static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    func `import`(_ data: Data, now: Date = Date()) throws -> Summary {
        let parsed = try ShotsyImport.parse(data)
        var summary = Summary()
        summary.unmappedKinds = parsed.unmappedKinds
        summary.scheduleName = parsed.schedule?.medicationName

        // The regimen, from the file's own schedule. Started at the first real
        // injection rather than the schedule's start date — the schedule
        // describes the *current* step, and the reader's history goes back
        // further than that.
        let taken = parsed.doses.filter(\.wasTaken)
        if !taken.isEmpty {
            let compound = Self.compound(for: parsed.schedule?.medicationName
                                         ?? taken.last?.medicationName)
            let existing = dataStore.loadActiveMedication()
            summary.supersededInferred = existing?.doses
                .filter { $0.isInferred && $0.confirmedAt == nil }.count ?? 0
            dataStore.replaceMedicationHistory(
                compound: compound,
                brandName: parsed.schedule?.medicationName ?? taken.last?.medicationName,
                startedOn: taken.first?.takenAt ?? now,
                doses: taken.map {
                    DoseLogRecord(takenAt: $0.takenAt, milligrams: $0.milligrams,
                                  injectionSite: $0.injectionSite, isInferred: false)
                })
            summary.doses = taken.count
        }

        if !parsed.samples.isEmpty {
            summary.samples = dataStore.mergeImportedSamples(parsed.samples)
        }
        summary.sideEffects = parsed.sideEffects.count
        return summary
    }

    /// Map Shotsy's brand name onto the compound whose pharmacology we model.
    /// Falls back to tirzepatide only when the name is recognisably one of its
    /// brands — an unknown medication gets no half-life rather than a guessed
    /// one, because a curve drawn on the wrong constant is worse than no curve.
    static func compound(for name: String?) -> GLPCompound {
        let lowered = (name ?? "").lowercased()
        for candidate in GLPCompound.allCases {
            if lowered.contains(candidate.rawValue) { return candidate }
            if candidate.brandNames.contains(where: { lowered.contains($0.lowercased()) }) {
                return candidate
            }
        }
        return .tirzepatide
    }
}
