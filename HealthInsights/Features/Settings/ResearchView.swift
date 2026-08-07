import SwiftUI
import InsightKit

/// **Why the cards decide the way they do.** Backlog P33.
///
/// This app withholds a lot — it refuses to alert, refuses to reassure, refuses
/// to train a model on a handful of examples — and every one of those refusals
/// is a conclusion from published work rather than a design preference. A reader
/// who cannot see the reasoning has to take the restraint on trust, and the
/// restraint is the most unusual thing about the app.
///
/// ## Where the text comes from, and why only from there
///
/// **`docs/research-notes.md`, and nothing else.** The full research reports
/// quote the reader's own physiology — noise floors, coverage, band membership —
/// and live outside this repo for that reason (`docs/privacy-and-ip.md`). What
/// is rendered here is the published-literature half: population findings,
/// citable and true of anyone. Nothing on this screen is about the reader.
///
/// If you are extending it, that rule is the whole design: **a line may be added
/// here only if it would be equally true printed in a journal.** The moment a
/// figure describes this reader, it belongs on a card, not in the reasoning.
///
/// ## Why it is one topic and says so
///
/// The notes cover early illness detection thoroughly and the other research
/// runs only in outline. Rendering a thin "Body" and "Charts" section beside a
/// deep one would imply an evenness that does not exist, so the screen names
/// what it covers, names the cards that reasoning drives, and stops.
struct ResearchView: View {

    var body: some View {
        List {
            introSection
            ForEach(ResearchTopic.all) { topic in
                Section {
                    ForEach(topic.findings) { finding in
                        FindingRow(finding: finding)
                    }
                } header: {
                    Text(topic.title)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(topic.appliedTo)
                        Text(topic.sources).italic()
                    }
                }
            }
        }
        .navigationTitle("Research")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var introSection: some View {
        Section {
            Text("Every refusal in this app — not to alert, not to reassure, not "
                 + "to guess — comes from published work rather than from taste. "
                 + "This is that work, in the order it changed a decision.")
                .font(.callout)
        } footer: {
            Text("Population findings only. Nothing here is about you, and no "
                 + "figure on this screen was read off your own record.")
        }
    }
}

/// One finding, and the decision it forced.
///
/// The pairing is the point. A research summary that stops at the finding leaves
/// the reader to guess what the app did about it, and the guess is usually
/// "nothing" — which is exactly the suspicion an in-app research section exists
/// to answer.
struct ResearchFinding: Identifiable {
    let id = UUID()
    let claim: String
    let detail: String
    /// What the app does differently because of it. Never omitted: a finding
    /// with no consequence is trivia, and trivia is what makes a section like
    /// this go unread.
    let consequence: String
}

private struct FindingRow: View {
    let finding: ResearchFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(finding.claim)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(finding.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(finding.consequence)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(finding.claim). \(finding.detail) "
                            + "What the app does: \(finding.consequence)")
    }
}

struct ResearchTopic: Identifiable {
    let id = UUID()
    let title: String
    let findings: [ResearchFinding]
    /// Which cards this reasoning actually drives, named so the screen can be
    /// read backwards from a card the reader is puzzled by.
    let appliedTo: String
    let sources: String
}

extension ResearchTopic {

    /// Verbatim in substance from `docs/research-notes.md` ▸ *Early illness
    /// detection: what is actually achievable*. Rewritten for the reader's
    /// register, not for its content — the numbers, the papers and the
    /// conclusions are the notes', and changing one here without changing it
    /// there would give the app two answers.
    static let all: [ResearchTopic] = [illnessDetection]

    static let illnessDetection = ResearchTopic(
        title: "Spotting an illness early",
        findings: [
            ResearchFinding(
                claim: "The headline accuracy is not a pre-symptom number.",
                detail: "The best-known result — 43.7% of infections caught at 95% "
                    + "specificity, from a convolutional network trained on 2,745 "
                    + "confirmed cases — is dominated by days the person already "
                    + "knew they were ill. On the night before symptoms it is 15%. "
                    + "The day they start, 24%.",
                consequence: "The radar is tuned for the night before, so it is "
                    + "built against the 15% and never quotes the 43.7%."),
            ResearchFinding(
                claim: "A quiet night is nearly worthless as reassurance.",
                detail: "It moves the odds of being ill from roughly 7% to roughly "
                    + "4% — a shift too small to act on.",
                consequence: "A quiet radar never reads as an all-clear. It says "
                    + "what it looked at, not that you are well."),
            ResearchFinding(
                claim: "The base rate, not the model, decides how often it is right.",
                detail: "Adults get 2–4 colds a year, so about 2.5% of nights sit in "
                    + "a window worth flagging. At the published accuracy that is "
                    + "roughly 22 alarms a year, about 18 of them wrong. The only "
                    + "prospective study to publish a predictive value reached 4% — "
                    + "96 alerts in 100 wrong, with a good model on dense data.",
                consequence: "Sensitivity is traded away for specificity on purpose. "
                    + "A card that cries wolf destroys the one true warning that "
                    + "arrives every few years — 88.8% of ICU arrhythmia alarms are "
                    + "false, and the documented response is that people stop "
                    + "listening."),
            ResearchFinding(
                claim: "No neural network, and that is a considered choice.",
                detail: "Supervised learning needs labelled illnesses. One person has "
                    + "a handful at best — which kills the training and, worse, the "
                    + "testing, because there is no denominator to measure accuracy "
                    + "against. Every shipped consumer feature is unsupervised "
                    + "baseline deviation, not a trained classifier. The best "
                    + "published real-time result is a state machine over a running "
                    + "median of overnight resting heart rate; a personal deep model "
                    + "managed recall of 0.36.",
                consequence: "Simple methods, whose false-alarm rate can be stated. "
                    + "Quoting a personal accuracy figure honestly would need about "
                    + "10 illnesses — three to five years of them."),
            ResearchFinding(
                claim: "Wearing the sensor more nights beats any modelling change.",
                detail: "Detection works by persistence across consecutive covered "
                    + "nights, so gaps cost more than algorithms gain. Garmin's own "
                    + "published floor is four nights a week.",
                consequence: "Coverage is shown rather than assumed — which nights "
                    + "the instruments actually reported, and which cards are "
                    + "therefore abstaining."),
            ResearchFinding(
                claim: "Score a run of nights, never a single night.",
                detail: "Sequential change detection is provably optimal for how fast "
                    + "you can spot a shift at a fixed false-alarm rate, and it beat "
                    + "a single-night detector on both axes at once: 80% against 72% "
                    + "sensitivity and 87.7% against 83.7% specificity. How long an "
                    + "alert lasts separates real from spurious — about 1.9 days for "
                    + "non-illness against 4.3 for infection.",
                consequence: "Runs are scored, not nights, and a short-lived "
                    + "deviation is allowed to pass without a word."),
            ResearchFinding(
                claim: "Thresholds come from your own history, never a statistics "
                    + "table.",
                detail: "Textbook three-sigma rules fire several times more often "
                    + "than their nominal rate on real personal data, because the "
                    + "residuals are heavier-tailed and more correlated than the "
                    + "textbook assumes.",
                consequence: "The threshold is replaced by a stated budget — tell me "
                    + "about the most unusual stretches a year — and the rate it "
                    + "actually achieved is displayed."),
            ResearchFinding(
                claim: "One joint statistic, never several thresholds OR'd together.",
                // count-in-copy: exempt — 6 is the arithmetic in the example, not
                // the number of signals any card reads.
                detail: "6 signals each at 95% specificity, OR'd, gives a 26.5% "
                    + "nightly false-positive rate — about 97 false-alarm nights a "
                    + "year. Holding 5% overall would demand 99.15% from each.",
                consequence: "Deviations are combined into a single statistic before "
                    + "anything is judged against a threshold."),
            ResearchFinding(
                claim: "Only the illness direction counts.",
                detail: "Every study converges on one signature: heart rate up, "
                    + "respiratory rate up, temperature up, HRV down, SpO2 down.",
                consequence: "Healthy-direction deviations are clamped to zero, which "
                    + "halves false alarms for free and imports several studies' "
                    + "worth of prior without training on anything."),
            ResearchFinding(
                claim: "How you feel is worth more than the whole sensor stack.",
                detail: "Symptoms alone score 0.71; sensors alone about 0.72; both "
                    + "together 0.80. In a 1,688-person influenza cohort, 41 wearable "
                    + "features including 29 HRV measurements added nothing over "
                    + "eight yes/no symptom questions. In the only large randomised "
                    + "trial the wearable arm carried literally zero information "
                    + "while the symptom diary carried a great deal. The specific "
                    + "question matters enormously: \"chills you couldn't warm up "
                    + "from\" is worth roughly the entire sensor stack, whereas "
                    + "\"feeling off\" is worth little.",
                consequence: "You are asked how you feel, in specific words, and the "
                    + "answer outranks the sensors."),
            ResearchFinding(
                claim: "More inputs help, but only genuinely independent ones.",
                detail: "Combining signals lifts accuracy from a coin flip to 0.72. "
                    + "But heart rate and HRV come from one heartbeat-interval "
                    + "stream and must not count as two agreeing votes. The truly "
                    + "independent channels — respiratory rate, temperature, SpO2 — "
                    + "are also the quietest.",
                consequence: "Closing a coverage gap in respiratory rate is worth "
                    + "more than any further modelling, and is asked for first."),
            ResearchFinding(
                claim: "Of everything that could confound this, only sleep survives.",
                detail: "Fitted and then cross-validated on contiguous blocks of "
                    + "time, sleep timing and efficiency predict resting heart rate "
                    + "and HRV out of sample, replicating across devices — so it is "
                    + "physiology, not one vendor's internal consistency. Previous-"
                    + "day activity, medication level, day of week, substances, body "
                    + "mass and calendar load all cross-validated to almost nothing, "
                    + "and usually worse than predicting the average.",
                consequence: "Confounders are handled by exclusion and annotation "
                    + "rather than by subtraction: a perturbed night is kept out of "
                    + "the baseline, and the alternative explanation is named on the "
                    + "card instead of being silently removed."),
            ResearchFinding(
                claim: "Alcohol is the best-documented confounder in this literature.",
                detail: "A moderate drinking evening moves nocturnal resting heart "
                    + "rate by about +3 bpm with suppressed HRV — the same size and "
                    + "shape as the illness signal.",
                consequence: "A detector without drink logging is partly an alcohol "
                    + "detector in an illness costume, which is why the substance log "
                    + "feeds it and why every chart is shaded where something was "
                    + "logged."),
            ResearchFinding(
                claim: "GLP-1 medication moves the same numbers.",
                detail: "Roughly +2 to +3.5 bpm on resting heart rate on average, "
                    + "with larger swings while the dose is being raised — enough "
                    + "that an unreset baseline reads a dose step as a week of "
                    + "illness.",
                consequence: "A dose change resets the baseline and is named as a "
                    + "possible explanation, never asserted as the cause."),
        ],
        appliedTo: "This reasoning drives the symptom radar, the early-warning half "
            + "of Readiness, and how much every card is willing to claim about a "
            + "quiet result.",
        sources: "Natarajan, Su & Heneghan, npj Digital Medicine 2020 · Mishra et "
            + "al., Nature Biomedical Engineering 2020 · Quer et al. (DETECT), "
            + "Nature Medicine 2021 · Radin et al., Lancet Digital Health 2020 · "
            + "Alavi et al., Nature Medicine 2022 · Grzesiak et al., JAMA Network "
            + "Open 2021 · COVID-RED randomised trial · Fitbit CNN, JMIR Form Res "
            + "2024 · Heikkinen & Järvinen, Lancet 2003 · Tokars et al., CID 2018 · "
            + "Page 1954; Lorden 1971; Moustakides 1986.")
}
