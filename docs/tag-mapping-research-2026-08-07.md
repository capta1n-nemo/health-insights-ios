# Mapping arbitrary user-created tags to categories, on-device

<!-- status: complete — buildable with NLEmbedding rather than Apple Intelligence — but measured at n=0 today, because OuraProvider never requests the tag scope -->

**Backlog §B12-2 · research, 2026-08-07 · no code written**

---

## Summary

The feature is buildable and the mechanism is mostly already in this repo — but the first finding is that **its data source is measured at zero**. I grepped the 2026-08-07 export (`~/HealthSeed/exports/health-insights-export-new.json`, 172 MB) for every key containing `tag`: the only matches were `bodyFatPercentage` and `bodyWaterPercentage`. There are no Oura tags in this app, in any window, because `OuraProvider` does not request the `tag` OAuth scope and does not call either tag endpoint — so B12-2 currently has n = 0 and every accuracy figure below is a *design for measurement*, not a measurement. The second finding is that the interesting question is smaller than it looks: Oura's schema splits tags into three classes, and only two of them are judgement calls, exactly as `CalendarEventClassification` already argues about calendar events. The third is that **the on-device model is the wrong place to put the floor**. `SystemLanguageModel` needs iOS 26 and an Apple-Intelligence-eligible device (this app deploys to iOS 18), its output can change when Apple ships a new model version with an OS update — Apple documents three such versions already — and it throws on guardrail violations and refusals, which a health app tagging "sick" and "alcohol" is specifically exposed to. The scaling requirement ("must work for tags never seen before") can be met *without* Apple Intelligence, by `NLEmbedding.sentenceEmbedding` nearest-centroid on iOS 14+, which is deterministic and revision-pinnable. So: rules where the answer is a fact, embeddings where it is a similarity, the language model only as a refinement, `.unclassified` as a first-class visible outcome, one persisted decision per *distinct normalised tag string* stamped with its provenance, and the reader's correction stored beside the guess rather than merged into it — the shape `CalendarEventJudgement` already proved out here.

---

## 1. Measured state: this data is not arriving

Counted, not assumed, per the standing rule.

```
$ grep -o '"[a-zA-Z_]*[Tt]ag[a-zA-Z_]*"' health-insights-export-new.json | sort | uniq -c
 621 "bodyFatPercentage"
 154 "bodyWaterPercentage"
```

Zero tag rows in the last 90 days, or any other window. The cause is in the code, not in the export:

- `HealthInsights/Core/Integrations/OuraProvider.swift:57` requests
  `["daily", "workout", "session", "spo2", "spo2Daily", "personal", "stress", "heart_health"]`.
  Oura's OAuth2 scope table (from its own OpenAPI spec, below) names the scope **`tag` — "User entered tags"**. It is not requested.
- `OuraProvider.rawCollections` (`daily_sleep`, `daily_stress`, `daily_resilience`, `daily_cardiovascular_age`, `vO2_max`) and `mappedCollections` (`sleep`, `daily_readiness`, `daily_spo2`, `daily_activity`) contain neither `tag` nor `enhanced_tag`.

Three consequences for whoever builds B12-1:

1. **The reader must re-authorise Oura.** Adding a scope does not widen an existing grant. Say so in the UI before the disconnect/reconnect, or it will read as a bug.
2. Add `"enhanced_tag": "tag"` (and `"tag": "tag"`) to `OuraProvider.requiredScope`. That map exists precisely because Oura answers a missing scope with 401 and names the scope only in the RFC 7807 `detail`; without the entry, a partial grant produces an unexplained failure line in `DiagnosticsLog` instead of "you didn't grant tags".
3. Until then, **nothing in this document has been run against real data.** Any claim below that says "verify on the phone" means it.

---

## 2. The shape of the input — authoritative, from Oura's own spec

Fetched from `https://cloud.ouraring.com/v2/static/json/openapi-1.37.json` (the spec URL the Redoc page at `cloud.ouraring.com/v2/docs` points at). Two live endpoints, neither marked deprecated, both `start_date` / `end_date` / `next_token` / `fields`:

| Endpoint | Model |
|---|---|
| `GET /v2/usercollection/enhanced_tag` | `EnhancedTagModel` — the structured one |
| `GET /v2/usercollection/tag` | `TagModel` — the legacy note-shaped one |

**`EnhancedTagModel`** — required: `id`, `start_time`, `start_day`.

| Field | Type | Oura's own description |
|---|---|---|
| `tag_type_code` | `string?` | "The unique code of the selected tag type, `NULL` for text-only tags, or `custom` for custom tag types." |
| `start_time` / `end_time` | local datetime, `end_time` nullable | timestamp, or start/end for a tag with duration |
| `start_day` / `end_day` | date, `end_day` nullable | as above, at day resolution |
| `comment` | `string?` | "Additional freeform text on the tag." |
| `custom_name` | `string?` | "The name of the tag if the `tag_type_code` is `custom`." |

**`TagModel`** (legacy) — `id`, `day`, `text`, `timestamp`, `tags: [String]`.

Observed code examples in the wild: `tag_sleep_alcohol`, `tag_sleep_stress` (MyDataHelps' Oura export docs), `tag_generic_nocaffeine` (the `oura-ring` PyPI client's sample). Oura's own help article says the app ships **"over 100 searchable tags"** — alcohol, caffeine, fasting, headache, late meal, meditation, melatonin, nap, sauna, sick, stress, travel — and that users can create custom tags, which "won't appear on Oura on the Web".

⚠️ **Oura publishes no enumeration of `tag_type_code` values.** In the spec the field is a bare nullable string with a prose description. So a code table cannot be built from the docs; it has to be built by observation from the reader's own data, and must degrade gracefully for a preset code it has never seen.

### The decomposition that does most of the work

This splits into three classes, and **only two of them are judgement calls**:

| Class | Signal | Who decides | Stability |
|---|---|---|---|
| **A.** `tag_type_code` is a known preset code | the code itself | exact match — a `fact` | permanent, never re-derived |
| **B.** `tag_type_code == "custom"` | `custom_name` (free text, never seen before) | similarity → model | needs the whole machine below |
| **C.** `tag_type_code == NULL` (text-only) | `comment` only | similarity → model | as B, plus the highest guardrail exposure |

This is the same discipline `CalendarEventClassification.swift` already writes down — *"half of these six axes are not judgement calls… asking a language model to decide those would be slower, non-deterministic, and less accurate than reading them."* A preset Oura tag code is a fact. Putting a language model between the reader and `tag_sleep_alcohol` is the same mistake as asking it how long a meeting was.

The backlog's warning ("a fixed lookup table is not an answer") is about class B and C. A lookup table is exactly the right answer for class A, and by row count it will be most of them.

---

## 3. What Apple's on-device Foundation Models can actually do here

### Availability — and why it cannot be the floor

`SystemLanguageModel.availability` is `.available` or `.unavailable(UnavailableReason)`. The reasons, from Apple's documentation, are exactly three:

| Reason | Apple's description | Recoverable? |
|---|---|---|
| `deviceNotEligible` | "The device does not support Apple Intelligence." | No |
| `appleIntelligenceNotEnabled` | "Apple Intelligence is not enabled on the system." | Only by the reader, in Settings |
| `modelNotReady` | "The model(s) aren't available on the user's device." | Yes — assets still downloading; retry later |

The framework starts at iOS 26.0. **This app's deployment target is iOS 18.0** (`HealthInsights.xcodeproj/project.pbxproj`), and `FoundationModelSummarizer` / `CalendarEventInterpreter` already guard it with `#if canImport(FoundationModels)` + `#available(iOS 26.0, *)` — the second of those guards cost a red CI when it was missing, and the file says so. Unavailability is not an edge case here; it is a large fraction of possible runs, and it is *every* run in InsightKit's Linux test suite.

### Structured output — use guided generation, not the tagging adapter

`@Generable` with a Swift enum constrains the model to emit only declared cases. Apple's content-tagging guide demonstrates the pattern with `@Guide(description:.maximumCount(n))`. This is the answer to "the model invented a category": it cannot.

⚠️ **`SystemLanguageModel(useCase: .contentTagging)` is the wrong tool for B12-2, despite the name.** Apple's own page — *Categorizing and organizing data with content tags* — describes it as producing "a list of categorizing tags based on the input text you provide… one to a few lowercase words", and says explicitly that if your constraints are "more complicated than the maximum count support of the tagging model, use [the general model] instead", and that content not in the action/object/emotion/topic families should use the general model too. That adapter *generates open-vocabulary tags from prose*. We already have the tag; we need to place it in a **closed** set. That is `SystemLanguageModel.default` plus a `@Generable` enum.

There is one legitimate secondary use: distilling a long class-C `comment` down to one or two topic tags before classifying it. Optional, and it doubles the model calls — I would not ship it in v1.

### The context window is 4,096 tokens, total

From Apple's documentation of `exceededContextWindowSize`: the limit "includes instructions, prompts, and outputs for a session instance", and "a single token corresponds to approximately three to four characters in languages like English". A `LanguageModelSession` accumulates a `Transcript`, so a long-lived session classifying tag after tag *will* exhaust it.

Derived budget (checkable arithmetic, not a citation): instructions ~120 tokens, and a round trip of one short tag plus one enum case ~15 tokens ⇒ roughly **(4096 − 120) / 15 ≈ 265 tags in one session** before it throws. At 25 tokens per round trip it is ~159. That is an upper bound on a best case, and the engineering answer is not to rely on it: **one session per tag, or a fresh session every N tags.** A fresh session also removes the contamination Apple warns about in the tagging guide — "when you reuse the same [session], the model may produce tags related to the previous turn".

### Determinism knobs, and why they are not enough

`GenerationOptions` exposes `samplingMode`: `.greedy` ("always chooses the most likely token"), `.random(top:seed:)`, `.random(probabilityThreshold:seed:)` — both random modes take a seed. So a repeatable decode is *requestable*.

⚠️ **Requesting greedy decoding is not the same as getting a stable answer.** The one hard published result on this is Thinking Machines Lab (2025), *Defeating Nondeterminism in LLM Inference*: sampling **1,000** completions of Qwen3-235B-Instruct at temperature 0 produced **80 distinct outputs**, first diverging at token 103; the cause identified was batch-size dependence of reduction kernels (matmul, RMSNorm, attention), not RNG, and batch-invariant kernels restored bit-identical output across 1,000 runs on Qwen3-8B.

Two honest caveats on transferring that here: it is a server-GPU, batched-serving result on a different model, and the on-device single-request path has a constant batch size of 1, which is the condition under which the paper's mechanism does *not* bite. **I could find no published measurement of run-to-run determinism for Apple's on-device Foundation Model.** So the correct posture is neither "it's deterministic" nor "it isn't": **cache the decision and never re-derive it**, which makes the question moot (§5).

### The stability threat Apple documents itself: model versions

From Apple's `SystemLanguageModel` page: *"Apple periodically updates SystemLanguageModel in routine OS updates… Currently there are 3 model versions that align with:"*

- iOS/iPadOS/macOS/visionOS **26.0 – 26.3**
- iOS/iPadOS/macOS/visionOS **26.4**
- iOS/iPadOS/macOS/visionOS/watchOS **27.0**

Apple's companion guide *Updating prompts for new model versions* tells developers to record prior outputs, compare against the new version, and version their prompts behind `#available` checks.

**This is the real answer to "how do I keep a tag from changing category under the reader": an OS update can change the model with no app change at all.** No amount of `.greedy` prevents that. Only a persisted decision does.

### Failure modes, exhaustively

`LanguageModelSession.GenerationError` cases, from Apple's docs:

| Case | What it means | Relevance to B12-2 |
|---|---|---|
| `guardrailViolation` | safety guardrails tripped by prompt **or** output | **High.** See below. |
| `refusal` | the model refused to answer | **High.** Under guided generation there is *no placeholder* — Apple's safety guide states it throws. |
| `exceededContextWindowSize` | 4,096 tokens used up | High for a batched first import |
| `concurrentRequests` | a second prompt while the first is still answering | High — an import of N tags must serialise or use N sessions |
| `rateLimited` | session rate limited | Medium; conditions unpublished. A first-import burst is exactly the shape that would hit it — batch with backoff |
| `unsupportedLanguageOrLocale` | asked to answer in an unsupported language | Medium — a custom tag may be in any language |
| `decodingFailure` | could not deserialise the `@Generable` type | Low but must fall through, not default |
| `unsupportedGuide` | a `@Guide` pattern the model can't honour | Build-time; catch in tests |
| `assetsUnavailable` | required assets missing | Overlaps `modelNotReady` |

⚠️ **The guardrail exposure is specific to this app, and it is on the most interesting tags.** Apple's safety guide says guardrails "aim to block harmful or sensitive content, such as self-harm, violence, and adult materials, from both model input and output". Oura's preset list already includes *sick* and *alcohol*; a class-B custom name or a class-C freeform comment is unbounded and is about the reader's health. So:

- The fallback must fire **on a throw**, not only on `.unavailable`. A tag that trips a guardrail must land in `.unclassified` via the deterministic path, silently, and **must not** show the reader a message implying their tag was objectionable. Apple's guide suggests surfacing the refusal explanation; here that would be a health app telling a person their symptom is unacceptable. Don't.
- The prompt must never put the tag text into the *instructions*. WWDC25-286's own rule: instructions come from the developer, never from the user. The tag goes in the prompt, and the instructions state the closed task.

### Latency: no published figure exists

I could not find any Apple-published or credibly-measured third-party figure for tokens/second or time-to-first-token for the Foundation Models framework model on any iPhone. Apple's *Updates to Apple's On-Device and Server Foundation Language Models* states the architecture change — KV-cache sharing "reducing the KV cache memory usage by 37.5% and significantly improving the time-to-first-token" — and publishes **no number**. The 2025 tech report (arXiv:2507.13575) describes the ~3B on-device model with 2-bit quantization-aware training and does not publish device-level latency either. WWDC notes put the model at "3 billion parameters each quantized to 2 bits" and characterise it as "not designed for world knowledge or advanced reasoning" but strong at "Summarization, Extraction, Classification, Tagging".

**So: put no latency claim in the app, and no latency claim in the docs.** Measure it (Apple points at Instruments and `LanguageModelSession.prewarm()`), over the reader's own distinct-tag set, and report median and p95. Until it is measured, classification is background work that must never block the Data tab or the import.

### Cost shape — derived, and it changes the design

**Classify distinct normalised tag strings, not tag events.** Oura's ~100+ presets all land in class A (zero model calls). Custom tags are the reader's own invented vocabulary — realistically tens. So lifetime model calls are `O(distinct custom tag names)`, and the marginal cost after the first import is *one call per newly invented tag*. A per-event design is wrong by the ratio of events to distinct names, which for a daily-tagging user over a year is two orders of magnitude.

---

## 4. The deterministic fallback: four tiers, none of them optional

Ordered. **Each tier only runs on what the tier above it could not settle**, and — the rule borrowed from `CalendarEventClassifier.refined` — **a lower tier's answer for something a higher tier settled is discarded, not preferred.**

**Tier 0 — exact match (`Decider.fact`).** `tag_type_code` in the observed preset table → its applicability. Permanent, offline, testable on Linux, never re-derived. Because Oura publishes no enumeration, the table is built from observation and *must* fall through for an unrecognised code rather than defaulting.

**Tier 1 — normalised lexicon (`Decider.rules`).** A small stemmed keyword set over `custom_name` / `tags[]`. This is "a fixed lookup table", and it is fine *as a floor*; the backlog rejects it as the whole answer, which it isn't.

**Tier 2 — on-device embedding, nearest centroid (`Decider.similarity`).** This is the piece that satisfies "must scale to tags never seen before" **without Apple Intelligence**, and I think it is the most valuable finding in this document.

`NLEmbedding.sentenceEmbedding(for:)` — Natural Language framework, **iOS 14+**, present on every device, no Apple Intelligence gate, no model download, no eligibility check. Compute `vector(for: normalisedTag)`, compare by cosine distance to a small set of category prototype vectors (each the mean of a handful of seed phrases), take the nearest.

Why this and not `wordEmbedding`: a word embedding is a **vocabulary lookup** (`contains(_:)`, `vocabularySize`) and returns nothing for an out-of-vocabulary token — which is exactly the "never seen before" case. A sentence embedding is computed from the text.

⚠️ **Verify on the phone before shipping (use the `use-the-phone` skill).** Two things I am not entitled to assert: that `sentenceEmbedding(for: .english)` is non-nil on the reader's device (it returns an Optional), and that `vector(for:)` returns a usable vector for an invented single-word compound such as `"kayaking"`. Both are plausible; neither is documented as guaranteed, and I found no published quality figure for Apple's sentence embedding on short single-word inputs.

Two properties that matter for §5:
- **It is revision-pinnable.** `NLEmbedding.sentenceEmbedding(for:revision:)`, `currentSentenceEmbeddingRevision(for:)`, `supportedSentenceEmbeddingRevisions(for:)`. Record the revision used with each decision, so an OS bump is *visible* rather than silent.
- **It is per-language.** Run `NLLanguageRecognizer` first; a tag in a language with no embedding falls to Tier 3, it does not get an English guess.

**Confidence gate (this is the error bar, and it is derived):** the decision is only taken when the **margin** between the nearest and second-nearest centroid exceeds a threshold. Below the margin → Tier 3. Set the threshold from the reader's own labelled set (§6), not from a number invented here. `NLContextualEmbedding` (iOS 17+) is a stronger option but requires asset download and `hasAvailableAssets` checks — worth a second look only if Tier 2 measures badly.

**Tier 3 — `.unclassified`.** A **real, displayed** category, not a hidden bucket. Per the honest-version rule, a tag whose applicability nothing can establish appears in the Tags section labelled "Not categorised", with a one-tap way for the reader to say what it is. A permanent null would be the useless option; a visible "we don't know, tell us" is the error bar.

**And then the model, as refinement.** `SystemLanguageModel.default` + `@Generable` enum, run **only** on tags that reached Tier 3 (or landed inside the Tier-2 margin), and only when `.available`. Its answer is recorded as `Decider.model`. On any throw — guardrail, refusal, rate limit, context, decode — the tier-3 answer stands, silently.

Note the ordering is the opposite of the intuitive one: the model does not go first and get corrected. It goes *last* and only touches what nothing cheaper could settle. That keeps the common case free, deterministic, testable on Linux, and identical on every device.

---

## 5. Keeping a classification stable across launches

Three separate drift sources. Each needs its own mechanism; conflating them is how a tag silently changes category.

**(a) Same input, same model, different run.** Solved by *never re-deriving*. Persist the decision keyed on a **normalised tag key** — SwiftData `@Model`, one row per distinct key, not per tag event. This is `CalendarJudgementRecord`'s shape (`PersistenceModels.swift:349`), registered in `DataStore.swift`'s Schema. A launch reads the stored decision; it does not re-classify.

⚠️ **The normaliser is itself a version.** Lowercase, Unicode NFKC, trim, collapse internal whitespace — and **store `normaliserVersion`**, because changing normalisation silently re-partitions the cache and orphans every stored decision *and* every reader correction attached to the old keys. That is the quietest way this feature could break.

**(b) Model, prompt or embedding changes.** Store a provenance stamp beside every decision:

```
decidedBy            .fact | .rules | .similarity | .model | .reader
modelVersionBucket   "26.0-26.3" | "26.4" | "27.0"   ← Apple's own three buckets
promptVersion        e.g. "tag-applicability-v1.0"
normaliserVersion    Int
embeddingRevision    UInt?   ← from currentSentenceEmbeddingRevision
marginAtDecision     Double? ← for the similarity tier
decidedAt            Date
```

**Default: do not re-classify existing tags when the model version bumps.** Offer it — a "re-check tag categories" action in the Data tab that names what changed and how many rows it would touch — but never do it because the reader updated iOS. Apple's *Updating prompts* guide asks developers to version prompts behind `#available`; combine the two: a `26.4` prompt is used for *new* tags, and old decisions keep their stamp until the reader asks.

**(c) The category set changes** (a new `TagApplicability` case ships). This is the only case where re-running is correct by default — and only for rows whose stored decision was `.unclassified` or inside the Tier-2 margin. **Never over a `.reader` decision.**

The invariant, verbatim from `CalendarEventJudgement.reclassified`: **re-running replaces the guess and leaves the correction exactly where it was.**

---

## 6. Reader correction that sticks

Reuse the judgement shape this repo has already argued through — do not invent a second one.

```
TagApplicabilityJudgement
  tagKey          normalised distinct tag string  (the identity)
  classification  what the app worked out, untouched by any correction
  correction      what the reader said, where they said anything
  artifact        snapshot of what was classified
  isConfirmed     reader looked and agreed (≠ not yet looked at)
  reviewedAt      Date?
  effective       correction ?? classification     ← what the rest of the app uses
```

**The correction is stored beside the guess, never merged into it.** `CalendarEventClassification.swift` already states why, and the reasoning carries over exactly: merged, a correction is indistinguishable from a good guess, so the app can never tell how often it was right, and any re-classification silently overwrites the reader.

**`Decider` gains a case.** Reuse `.fact` / `.rules` / `.model` / `.reader`, and **add `.similarity`** for the embedding tier. Do not fold similarity into `.model`: the two have different error characters (one is a geometric near-miss, the other a semantic misreading), and merging them makes the accuracy figure meaningless — which is the same argument the existing `Decider` doc-comment makes about rules versus model.

**The artifact, and a privacy decision that is owed.** The snapshot should carry `tag_type_code`, `custom_name`, and *the fact that a comment was present*. ⚠️ Per `docs/privacy-and-ip.md` — *the shape of a finding, never the reading* — I would store a hash and a length for the `comment` rather than the comment text, because a tag comment is unstructured free text about one person's health in a **public** repo's data model, and it is the single most identifying string this feature will touch. **Decision owed from the reader:** does the artifact keep the comment text, or only its shape?

**Accuracy, with a derived error rather than a cited one.** `TagClassifierAccuracy.measure(_:)`, mirroring `CalendarClassifierAccuracy`: reviewed = confirmed + corrected; agreed = reviewed and not corrected. Withhold the rate below a minimum n, exactly as `CalendarClassifierAccuracy.rate` does. And **print an interval, not a bare percentage** — a Wilson 95% score interval, computed on device:

| agreed / reviewed | point estimate | Wilson 95% |
|---|---|---|
| 9 / 10 | 0.900 | 0.596 – 0.982 |
| 18 / 20 | 0.900 | 0.699 – 0.972 |
| 27 / 30 | 0.900 | 0.744 – 0.965 |
| 45 / 50 | 0.900 | 0.786 – 0.957 |
| 90 / 100 | 0.900 | 0.826 – 0.945 |

That table is the honest picture and it argues for a minimum n around 20–30 before showing anything: at n = 10 the app cannot distinguish 60% accuracy from 98%. Nothing is cited here — it is arithmetic the reader can check.

**⚠️ How a correction generalises — and why it must not do so retroactively.** If the reader moves *kayaking* from Recreation to Activity & mobility, the tempting move is "apply to similar tags", using the Tier-2 neighbourhood. That is the single most likely way a tag changes category under the reader — it is a batch write triggered by an unrelated tap. Recommendation:

- Never auto-generalise a correction to already-classified tags.
- Instead, add the corrected tag's vector to that category's **centroid**, affecting only *future, not-yet-seen* tags. That is how a correction genuinely trains the cheap tier, without rewriting history.
- If the app ever does offer "also recategorise 4 similar tags", it must **name them and require a tap**, and rows it touches must record `.reader` provenance — not `.similarity`.

---

## 7. The applicability vocabulary

The reader's own example phrase is **already a string in this codebase**: `MetricDataCategory.activity = "Activity & mobility"` (`InsightKit/Sources/InsightKit/Models/MetricDataCategory.swift:24`). Reuse the wording. `DataDomain.swift` documents in its own comments the exact bug that comes from not doing so — *"two 'Hearing' headings — the exact two-taxonomies bug the nutrition section already paid for."*

But `MetricDataCategory` is a Data-tab grouping **for metrics** and cannot express what a tag means. A tag can be an illness, a mood, a substance, a place, an obligation. So: a **separate `TagApplicability` enum**, with an explicit `var metricCategory: MetricDataCategory?` bridge where one exists, so there is one taxonomy with a stated mapping rather than two taxonomies pretending to be one.

Proposed cases and where each routes — a starting point, not a ruling:

| `TagApplicability` | Bridges to | Routes to |
|---|---|---|
| Activity & mobility | `.activity` | fitness cards (B12-3 candidates) |
| Sleep & recovery | `.sleepRecovery` | sleep cards |
| Illness & symptoms | — | symptom radar (§B11-8's "Oura tags considered contextually") |
| Mental state | — | mental-health card |
| Nutrition | `.nutrition` | nutrition |
| Substances | — | `DataDomain.substances` |
| Body | `.body` | body |
| Heart & circulation | `.heart` | heart |
| Environment | — | tags section only |
| Life & logistics (travel, work, leave) | — | calendar / holiday ledger |
| **Not categorised** | — | tags section, with a correction affordance |

⚠️ **Keep the case count small.** Guided generation stops the model emitting an invalid case; it does not make a 3B model good at fine distinctions, and every case added creates new confusion pairs and widens the interval in §6. Ten to twelve is defensible. Twenty-five is not, and the way to add the twenty-fifth is to *measure* that the twelve are being confused.

**Two enforcement surfaces this feature must satisfy** (load the `add-data-or-input` skill first):

1. §B12-1's "new Tags data section" means a **new `DataDomain` case** — which will not compile until `DataTabView` renders it *and* says how it answers a search, and it needs a `DomainDataScaffold` detail page per `docs/data-conventions.md`.
2. The correction UI is **a new input surface** — `InputKind`, the Today `+` menu, Settings ▸ Add or update data, a `ContributionRoute`, and `verify.sh` fails on any `…Sheet` under `Features/` the master list cannot open.

---

## 8. What I could not establish — stated plainly

Each of these is a finding, and each is a reason not to print a number.

- **No published accuracy figure**, at any n, for zero-shot closed-set classification of short activity/health tags by Apple's on-device Foundation Model. None found. The only route to a number here is §6's own measurement.
- **No published latency or throughput figure** for the Foundation Models framework model on any iPhone. Apple describes the KV-cache improvement qualitatively and publishes no ms or tok/s.
- **No published determinism measurement** for Apple's on-device model. The Thinking Machines result is real (n = 1,000, Qwen3-235B, 80 distinct outputs at temperature 0) but is a batched-serving GPU result and does not transfer to a batch-of-1 on-device path without evidence.
- **No published quality figure** for `NLEmbedding.sentenceEmbedding` on short, single-word or invented inputs — the Tier-2 threshold must be fitted to the reader's own tags.
- **Oura publishes no `tag_type_code` enumeration.** "Over 100" comes from Oura's help article, not the API. The Tier-0 table is observational and must fall through.
- **The WWDC 2026 provider-abstraction claims** (third-party `LanguageModel` / `LanguageModelExecutor` protocols, `PrivateCloudComputeLanguageModel` at 32K context, MLX and Core AI model sources, Gemini/Anthropic launch partners) come from **a single secondary blog post**, not from Apple. I could not confirm them against Apple's own documentation in this session. **Do not design against them.** And note that even if true, they change nothing here: tag text is health data and must not leave the device, so the on-device path is the only permitted one — a vendor cloud model could at most be a *labelled second opinion*, never blended into the stored classification.

---

## 9. Build order, and the decisions owed

**Order** (each step is shippable and testable on Linux except where noted):

1. **B12-1 first, properly.** Add the `tag` scope + `enhanced_tag`/`tag` collections to `OuraProvider`, add both to `requiredScope`, tell the reader they must re-authorise. Then **count the rows again** — everything downstream is unmeasurable until this is non-zero.
2. `TagApplicability` enum + `DataDomain.tags` + the Data-tab section + `DomainDataScaffold` page. Tier 0 and Tier 1 only. Fully deterministic, fully tested on Linux, ships to the phone.
3. The persistence layer: `TagApplicabilityJudgement`, the normalised key, the provenance stamp, the correction path, `TagClassifierAccuracy` with the Wilson interval. Still no model.
4. Tier 2 (`NLEmbedding`), behind an on-device verification of the two Optionals in §4. Fit the margin threshold to the reader's labelled set.
5. Tier 3 refinement with `SystemLanguageModel`, guarded exactly as `CalendarEventInterpreter` guards it, catching every `GenerationError` case into the tier-3 answer.
6. Only then B12-3 — activity tags as *card candidates at the next review*, never wired automatically.

**Decisions owed from the reader:**

- The `TagApplicability` case list — is the eleven above right, and is "Not categorised" acceptable as a visible category?
- **Artifact privacy**: does the stored snapshot keep the tag `comment` text, or only its shape (hash + length + presence)? This repo is public.
- **Re-classification policy on an OS model bump**: silent never; is it "offer it in the Data tab" or "never at all"?
- **Correction generalisation**: prototype-only for future tags (my recommendation), or a named-and-confirmed batch recategorise?
- Whether the legacy `/tag` endpoint is imported at all, or only `/enhanced_tag`.

---

## Sources

**Apple (primary, from developer.apple.com documentation JSON):**
- [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) — three model versions (26.0–26.3, 26.4, 27.0); use-case adapters
- [SystemLanguageModel.Availability.UnavailableReason](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason) — the three reasons
- [Categorizing and organizing data with content tags](https://developer.apple.com/documentation/foundationmodels/categorizing-and-organizing-data-with-content-tags) — `contentTagging` behaviour, `@Generable`/`@Guide`, "use the general model instead"
- [Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions) — prompt versioning behind `#available`
- [LanguageModelSession.GenerationError](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror) — the nine cases; `exceededContextWindowSize` states the 4,096-token window
- [Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output) — guardrail scope, refusals throw under guided generation
- [GenerationOptions.SamplingMode](https://developer.apple.com/documentation/foundationmodels/generationoptions/samplingmode-swift.struct) — `.greedy`, `.random(top:seed:)`, `.random(probabilityThreshold:seed:)`
- [NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding) (iOS 13; `sentenceEmbedding(for:)` iOS 14) and [NLContextualEmbedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding) (iOS 17)
- [Updates to Apple's On-Device and Server Foundation Language Models](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates) — ~3B params, 2-bit QAT, KV-cache 37.5%, 15 languages, no latency figure
- [Apple Intelligence Foundation Language Models Tech Report 2025](https://arxiv.org/abs/2507.13575)

**Oura (primary):**
- [OpenAPI spec 1.37](https://cloud.ouraring.com/v2/static/json/openapi-1.37.json) — `EnhancedTagModel`, `TagModel`, endpoints, OAuth2 scope `tag`
- [Using Tags — Oura Help](https://support.ouraring.com/hc/en-us/articles/360038676993-Using-Tags) — "over 100 searchable tags", custom tags

**Secondary (flagged as such):**
- [Defeating Nondeterminism in LLM Inference — Thinking Machines Lab, 2025](https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/) — n = 1,000, 80 distinct outputs at temperature 0
- [Oura Enhanced Tag Export Format — MyDataHelps](https://support.mydatahelps.org/oura-enhanced-tag-export-format) — example `tag_type_code` values
- [Meet the Foundation Models framework — WWDCNotes (WWDC25-286)](https://wwdcnotes.com/documentation/wwdc25-286-meet-the-foundation-models-framework/) — "3 billion parameters each quantized to 2 bits"; task list
- [WWDC 2026 provider abstraction — dev.to](https://dev.to/arshtechpro/wwdc-2026-apple-just-opened-the-foundation-models-framework-to-any-llm-provider-5ejn) — **unconfirmed against Apple; do not design against it**

**Repo evidence:** `HealthInsights/Core/Integrations/OuraProvider.swift:57` (scopes), `:66-68` (collections), `:74-80` (`requiredScope`); `HealthInsights/Core/Intelligence/CalendarEventInterpreter.swift` (the guard pattern, and the red CI it cost); `InsightKit/Sources/InsightKit/Models/CalendarEventClassification.swift` (`Decider`, `CalendarEventJudgement`, `reclassified`, `CalendarClassifierAccuracy`); `InsightKit/Sources/InsightKit/Models/MetricDataCategory.swift:24`; `InsightKit/Sources/InsightKit/Presentation/DataDomain.swift`; `HealthInsights.xcodeproj/project.pbxproj` (iOS 18.0 target); `~/HealthSeed/exports/health-insights-export-new.json` (the zero count).
