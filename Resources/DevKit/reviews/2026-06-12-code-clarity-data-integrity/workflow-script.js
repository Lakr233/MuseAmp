export const meta = {
  name: "museamp-clarity-integrity-review",
  description:
    "Loop-until-dry code-clarity review by scope + targeted data-integrity audit with adversarial verification",
  phases: [
    {
      title: "Understand",
      detail: "map all 13 scopes: structure, local conventions, data flows",
    },
    {
      title: "Review",
      detail:
        "clarity finders per scope + integrity finders per dimension, looped until dry",
    },
    {
      title: "Verify",
      detail: "adversarial verification of every fresh finding",
    },
    {
      title: "Critique",
      detail: "completeness critic over coverage and confirmed findings",
    },
  ],
};

const ROOT = "/Users/qaq/Documents/GitHub/MuseAmp";
const SKILL = "/Users/qaq/Documents/Skills/code-clarity/SKILL.md";
const MAX_ROUNDS = 4;

const SCOPES = [
  {
    key: "app-shell",
    title: "App lifecycle, environment, root shell, extensions",
    paths: [
      "MuseAmp/Application",
      "MuseAmp/Interface/Root",
      "MuseAmp/Extension",
      "MuseAmp/main.swift",
    ],
  },
  {
    key: "backend-api-library",
    title:
      "APIClient + local/remote library providers, importer, metadata reader",
    paths: ["MuseAmp/Backend/API", "MuseAmp/Backend/Library"],
  },
  {
    key: "backend-downloads",
    title: "Download orchestration and persisted download records",
    paths: ["MuseAmp/Backend/Downloads"],
  },
  {
    key: "backend-playback-models",
    title: "PlaybackController bridge + app-facing media models",
    paths: ["MuseAmp/Backend/Playback", "MuseAmp/Backend/Models"],
  },
  {
    key: "backend-playlist-lyrics",
    title: "Playlist CRUD/persistence/artwork + lyrics fetch/parse/convert",
    paths: ["MuseAmp/Backend/Playlist", "MuseAmp/Backend/Lyrics"],
  },
  {
    key: "backend-sync-support",
    title: "LAN sync protocol/sessions + supplements, logging, menu providers",
    paths: [
      "MuseAmp/Backend/Sync",
      "MuseAmp/Backend/Supplement",
      "MuseAmp/Backend/Logging",
      "MuseAmp/Backend/MenuProviders",
    ],
  },
  {
    key: "interface-browse",
    title: "Browse flows + shared collections/common UI",
    paths: [
      "MuseAmp/Interface/Browse",
      "MuseAmp/Interface/Collections",
      "MuseAmp/Interface/Common",
    ],
  },
  {
    key: "interface-nowplaying",
    title: "Now Playing controller, sections, components, lyric sheet",
    paths: ["MuseAmp/Interface/NowPlaying"],
  },
  {
    key: "interface-features",
    title: "Playlist, Search, Settings, Sync feature UI",
    paths: [
      "MuseAmp/Interface/Playlist",
      "MuseAmp/Interface/Search",
      "MuseAmp/Interface/Settings",
      "MuseAmp/Interface/Sync",
    ],
  },
  {
    key: "tvos",
    title:
      "tvOS shell target (lifecycle, root state machine, thin adapters, symlinked Sync)",
    paths: ["MuseAmpTV"],
  },
  {
    key: "databasekit",
    title:
      "MuseAmpDatabaseKit local library runtime (WCDB stores, scanner, caches)",
    paths: ["MuseAmpDatabaseKit/Sources"],
  },
  {
    key: "subsonickit",
    title: "SubsonicClientKit remote service layer",
    paths: ["SubsonicClientKit/Sources"],
  },
  {
    key: "playerkit",
    title: "MuseAmpPlayerKit playback engine",
    paths: ["MuseAmpPlayerKit/Sources"],
  },
];

const INTEGRITY = [
  {
    key: "rebuild-scan",
    focus:
      "The database rebuild pipeline: MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift (rebuildIndexFromDisk), DatabaseManager+Writes.swift (rebuildIndex, ingestAudioFile), DatabaseManager+Commands.swift. Hunt: index-vs-disk consistency, prune logic that could delete valid user files, .tmp handling, partial failure mid-rebuild leaving inconsistent state, snapshot staleness (fileSize+modifiedAt 0.5s tolerance), durationSeconds ?? 0 fallback writing bogus durations, swallowed errors (try?), progress callback correctness, deletedPaths computation (note: invalidRelativePaths.contains inside a filter is O(n*m)).",
  },
  {
    key: "rebuild-validation-gap",
    focus:
      "A REQUESTED FEATURE GAP AUDIT, not generic review. Today, during database rebuild and ingest, files are inspected via the inspectAudioFile dependency closure (wired in MuseAmp/Application/AppEnvironment+Bootstrap.swift and MuseAmpTV/Application/TVAppContext+Bootstrap.swift, both calling EmbeddedMetadataReader.makeTrackRecord in MuseAmp/Backend/Library/EmbeddedMetadataReader.swift). There is NO check that (a) the file is actually readable, (b) an audio player (e.g. AVAudioPlayer) can be created from it, (c) duration is sane (> 1 second and < 24 hours). Trace EXACTLY what happens today during rebuild and during ingestAudioFile when a file is: unreadable/permission-denied, truncated/corrupt, zero-duration, or has absurd duration. Report each concrete behavior gap as a finding with file:line. Also report: how EmbeddedMetadataReader is shared with the tvOS target (symlink? duplicate?) — run ls -la on MuseAmpTV/Backend and subdirectories to check; whether AudioFileImporter.swift has the same gap; what the scanner does when inspectAudioFile throws (prune behavior) and what ingestAudioFile does when it throws.",
  },
  {
    key: "index-state-store",
    focus:
      "MuseAmpDatabaseKit Internal/IndexStore.swift, StateStore.swift, Internal/WCDB/*.swift row types. Hunt: transactionality of multi-row operations (upsertTracks + deleteTracks not atomic together?), schema/model mapping mismatches, primary key / unique constraint gaps, trackID collisions across albums, date/precision round-trip loss, migration handling, error paths that leave DB and disk out of sync.",
  },
  {
    key: "downloads",
    focus:
      "MuseAmp/Backend/Downloads (DownloadStore, DownloadManager, +Digger, artwork/export processors). Hunt: record-vs-file consistency, crash/kill mid-download leaving orphan .tmp or orphan records, duplicate job submission, resume correctness, durationSeconds: nil at DownloadManager+Digger.swift:264 propagation, completed-download verification, retry state machines with impossible states.",
  },
  {
    key: "playlist",
    focus:
      "MuseAmp/Backend/Playlist (PlaylistStore, PlaylistTransferDocument, artwork cache) and MuseAmpDatabaseKit playlist models/rows. Hunt: referential integrity when tracks are deleted or rebuilt (dangling playlist entries), duplicate entry handling, transfer document round-trip fidelity (PlaylistTransferDocument), merge logic at PlaylistStore.swift around line 238-247, artwork cache invalidation, UUID stability.",
  },
  {
    key: "sync-transfer",
    focus:
      "MuseAmp/Backend/Sync (SyncProtocol, SyncTransferSession, sender/receiver, prepared track builder) and the MuseAmpTV/Backend/Sync symlink mirror. Hunt: protocol framing errors (length-prefix handling, partial reads), missing checksum/size validation of received files, partial-transfer cleanup, receiver-side ingest of corrupt/truncated files, concurrent session races, file name sanitization mismatches between sender and receiver, symlink mirror completeness (every Sync file the TV target needs must exist as symlink).",
  },
  {
    key: "playback-state",
    focus:
      "MuseAmp/Backend/Playback (PlaybackController and extensions: +Snapshot, +Delegate, restore/persist logic). Hunt: queue persistence/restore correctness (out-of-range indices, deleted tracks in restored queue), local-vs-remote URL resolution staleness (expired remote URLs persisted), time persistence precision, state snapshot drift between MusicPlayer and PlaybackController, race between restore and user-initiated playback.",
  },
  {
    key: "import-move",
    focus:
      "MuseAmp/Backend/Library/AudioFileImporter.swift and any file move/rename logic in MuseAmpDatabaseKit (DatabaseManager+Writes move/ingest, LibraryPaths). Hunt: non-atomic move+index sequences (file moved but index write fails, or vice versa), filename sanitization collisions overwriting existing files, duplicate detection using abs(duration diff) < 2.0 false positives/negatives, M4A-only document type assumptions vs other extensions on disk, tmp file leaks.",
  },
  {
    key: "caches",
    focus:
      "MuseAmpDatabaseKit CacheCoordinator (artwork/lyrics caches, orphan pruning) plus PlaylistCoverArtworkCache in the app. Hunt: pruneOrphanArtwork/pruneOrphanLyrics deleting valid data (e.g. when called mid-rebuild before upserts commit, or trackID set incomplete), try? swallowing write failures so cache silently diverges, cache key collisions, cache invalidation on track update (artwork changed but cache keeps stale entry).",
  },
];

const EXTRA_ROUND1 = [
  { kind: "clarity", key: "cross-target-duplication", prompt: null },
  { kind: "clarity", key: "docs-structure-sync", prompt: null },
];

const MAP_SCHEMA = {
  type: "object",
  required: ["scope", "summary", "conventions", "keyFiles"],
  properties: {
    scope: { type: "string" },
    summary: {
      type: "string",
      description:
        "5-10 sentence map of what lives here and how it is organized",
    },
    conventions: {
      type: "array",
      items: { type: "string" },
      description:
        "local naming/split/control-flow patterns observed in this scope",
    },
    keyFiles: { type: "array", items: { type: "string" } },
    dataFlows: {
      type: "array",
      items: { type: "string" },
      description: "data ownership and flow notes relevant to integrity review",
    },
  },
};

const FINDINGS_SCHEMA = {
  type: "object",
  required: ["findings"],
  properties: {
    findings: {
      type: "array",
      items: {
        type: "object",
        required: ["file", "title", "detail", "severity", "category"],
        properties: {
          file: {
            type: "string",
            description:
              "path relative to repo root, must be a real existing file",
          },
          line: { type: "number" },
          title: { type: "string", description: "short distinct title" },
          detail: {
            type: "string",
            description: "what is wrong, with concrete evidence from the code",
          },
          category: {
            type: "string",
            description: "clarity principle name or integrity dimension",
          },
          severity: { type: "string", enum: ["low", "medium", "high"] },
          suggestion: { type: "string", description: "concrete fix" },
        },
      },
    },
  },
};

const VERDICT_SCHEMA = {
  type: "object",
  required: ["real", "reasoning"],
  properties: {
    real: { type: "boolean" },
    conventionEndorsed: {
      type: "boolean",
      description:
        "true if AGENTS.md or dominant local convention explicitly endorses the flagged pattern",
    },
    adjustedSeverity: { type: "string", enum: ["low", "medium", "high"] },
    reasoning: { type: "string" },
  },
};

const CRITIQUE_SCHEMA = {
  type: "object",
  required: ["gaps", "notes"],
  properties: {
    gaps: {
      type: "array",
      items: { type: "string" },
      description:
        "concrete coverage gaps: scope not reviewed, dimension shallow, claim unverified",
    },
    notes: { type: "string" },
  },
};

const COMMON_RULES = `
GROUND RULES (apply to every reviewer):
- Repo root: ${ROOT}. You are READ-ONLY: never modify, create, or delete any file.
- FIRST read ${ROOT}/AGENTS.md — it defines mandatory local conventions. Per the code-clarity principle "Repository Conventions", a pattern explicitly mandated there is NOT a finding (e.g. closure-based RuntimeDependencies, FileManager.default direct use, Interface animation wrappers, 200pt hardcoded spacers, @unchecked Sendable + nonisolated fixes, hardcoded split patterns).
- Findings must cite a real file path relative to repo root and a line number. An adversarial verifier WILL open the file and try to refute you — vague or unverifiable findings get killed.
- Do not report: formatter-territory style (indentation, wrapping), test-file-only nitpicks, or anything whose fix would violate AGENTS.md.
- Your final output goes through the StructuredOutput tool only; it is data for a machine, not prose for a human.`;

function clarityChecklist() {
  return `THE 13 CODE-CLARITY PRINCIPLES (full text at ${SKILL} — read it if you need detail):
1. Naming — names reveal intent: verbs for actions, noun-phrases for values, is/has/can/should booleans, no vague Manager/Helper/Util/handle()/process(), parameters labeled meaningfully.
2. Early return — guard-first, happy path at leftmost indentation, no else-after-return, invert nesting.
3. Function design — one thing per function, no "and" functions, no boolean behavior flags, 0-2 params preferred, side effects named.
4. State modeling — related flags/optionals describing one lifecycle = hidden state machine; prefer one enum/state value; no stored one-shot Tasks; no optional-as-state.
5. Abstraction levels — no mixing orchestration with raw bit/string manipulation in one scope; step-down rule.
6. Repository conventions — clarity is local; match the repo's split/naming/control-flow habits (AGENTS.md is authoritative here).
7. Error boundaries — scoped do/catch, no casual try? for lifecycle/user-visible failures, best-effort failures still leave a log trace (AGENTS.md REQUIRES AppLog/DBLog on every swallowed error — flag silent catch/try? without logging).
8. Class/struct design — single responsibility, honest names, struct for values, no accumulation types.
9. File organization — one primary type per file, Type+Feature.swift extensions, filename = export, no grab-bag files.
10. Named constants — magic numbers/strings hoisted to named private constants at the right scope; repeated literals centralized.
11. Mechanical consistency — defer to the formatter; flag only hand-fought formatting that diverges from repo style.
12. (Electron boundaries — N/A for this codebase; skip.)
13. Dependencies & seams — one canonical implementation per behavior (flag duplicated inline logic across call sites), seams only where behavior varies, no speculative protocols, no closure-injected dependency bags EXCEPT the AGENTS.md-sanctioned RuntimeDependencies.`;
}

function mapPrompt(scope) {
  return `You are mapping one scope of the MuseAmp codebase (pure-UIKit iOS/tvOS music app) for a downstream review fleet.
Scope: ${scope.title}
Paths (relative to ${ROOT}): ${scope.paths.join(", ")}

Read AGENTS.md at the repo root first for context, then explore every Swift file in the scope paths (list them, read the important ones, skim the rest). Produce:
- summary: what lives here, how it is organized, what the central types are and who owns state
- conventions: the LOCAL patterns this scope actually follows (file splits, naming suffixes, guard usage, logging style)
- keyFiles: the 5-15 most important files (repo-relative paths)
- dataFlows: where data is created/persisted/transformed here, and which other layers it crosses (relevant for a data-integrity audit)
You are read-only. Output via StructuredOutput only.`;
}

function knownFindingsBlock(kind, scope) {
  const titles = [];
  for (const c of allRecorded) {
    if (c.kind !== kind) continue;
    if (kind === "clarity" && scope) {
      const inScope = scope.paths.some((p) => c.file.indexOf(p) === 0);
      if (!inScope) continue;
    }
    if (kind === "integrity" && scope && c.finder !== scope) continue;
    titles.push(`- ${c.file}${c.line ? ":" + c.line : ""} — ${c.title}`);
  }
  if (!titles.length) return "";
  return `\nALREADY-REPORTED ISSUES (do NOT re-report these or trivial variants of them — find genuinely NEW, distinct issues; return an empty findings array if there is nothing new):\n${titles.join("\n")}\n`;
}

function clarityPrompt(scope, map, round) {
  const mapBlock = map
    ? `\nSCOPE MAP (from a prior mapping agent):\nSummary: ${map.summary}\nLocal conventions: ${(map.conventions || []).join("; ")}\nKey files: ${(map.keyFiles || []).join(", ")}\n`
    : "";
  return `You are a code-clarity reviewer for the MuseAmp repo (round ${round}).
Scope: ${scope.title}
Paths: ${scope.paths.map((p) => ROOT + "/" + p).join(", ")}
${COMMON_RULES}
${clarityChecklist()}
${mapBlock}${knownFindingsBlock("clarity", scope)}
TASK: Review EVERY Swift file under the scope paths against the 13 principles. Rate mentally per file; report each concrete violation worth fixing as a finding. category = the principle name (e.g. "naming", "state-modeling", "error-boundaries", "file-organization", "named-constants", "seams-duplication"). Set severity by reader/maintenance impact, not by how easy the fix is. Every finding needs file, line, concrete evidence in detail, and a concrete suggestion that respects AGENTS.md. Quality over volume — but do not stop at the first few files; cover the whole scope.${round > 1 ? " This is a later round: dig into files and angles earlier rounds likely skimmed (smaller files, extensions, less-glamorous helpers, cross-file duplication within the scope)." : ""}`;
}

function integrityPrompt(dim, round) {
  return `You are a data-integrity auditor for the MuseAmp repo (round ${round}). You hunt REAL ERRORS: bugs, data loss, corruption, races, silent inconsistency between disk/database/UI state. Style is out of scope — another fleet handles that.
Dimension: ${dim.key}
${COMMON_RULES}
FOCUS: ${dim.focus}
${knownFindingsBlock("integrity", dim.key)}
TASK: Trace the relevant flows end-to-end through the actual code (open the files, follow the calls across package boundaries). For every concrete defect or integrity gap, produce a finding: category = "${dim.key}", file:line where the defect lives, detail = the exact failure scenario (what sequence of events corrupts/loses data or leaves state inconsistent), suggestion = concrete fix. Distinguish real defects from theoretical ones — a verifier will trace your scenario and kill anything that cannot actually happen.${round > 1 ? " This is a later round: probe edge cases and interactions earlier rounds likely missed (crash timing, concurrent operations, empty/huge inputs, cross-target tvOS paths)." : ""}`;
}

function crossCuttingPrompt(key, round) {
  if (key === "cross-target-duplication") {
    return `You are a cross-target duplication reviewer for the MuseAmp repo.
${COMMON_RULES}
TASK: Compare MuseAmp/ (iOS) and MuseAmpTV/ (tvOS) implementations. AGENTS.md says MuseAmpTV/Backend/Sync mirrors files via relative symlinks, and the TV target should stay a thin shell. Hunt: (1) near-verbatim duplicated code between the two targets that should be a shared implementation or symlink (e.g. compare AppEnvironment+Bootstrap.swift makeRuntimeDependencies vs TVAppContext+Bootstrap.swift — the inspectAudioFile closures look duplicated; find ALL such duplications with diff-level evidence); (2) symlink mirrors that are missing or stale (run ls -la on MuseAmpTV/Backend and subdirs); (3) drift between duplicated copies where one side got a fix the other did not. category = "seams-duplication". Findings need file:line evidence on BOTH sides.`;
  }
  return `You are a documentation-sync reviewer for the MuseAmp repo.
${COMMON_RULES}
TASK: AGENTS.md (= CLAUDE.md, symlinked) is the authoritative structure doc and REQUIRES that structural changes update it in the same change. Verify it against reality: (1) every directory/package it describes exists (note: it describes a MuseAmpInterfaceKit/ package — check whether it exists on disk and whether code still imports it or references its types like TableBaseCell, Interface, EmptyStateView — find where those types actually live now); (2) every real top-level directory and Interface/Backend subdirectory is documented; (3) described files exist at described paths (e.g. Interface/Common/Presenters/SongExportPresenter.swift, ConcurrencyHelpers.swift, the xcstrings files list); (4) described rules reference real types (PlaybackFeedbackPresenter, DownloadSubmissionFeedbackPresenter, ProgressActionPresenter, ConfirmationAlertPresenter, AppNotificationUserInfoKey, notification names amusic.*). Each mismatch = one finding, category = "docs-sync", file = AGENTS.md with the line of the stale claim, detail = what reality shows (with the real paths you verified).`;
}

function clarityVerifyPrompt(f) {
  return `You are an adversarial verifier for ONE code-clarity finding in the MuseAmp repo (root: ${ROOT}). Your job is to REFUTE it if you can. Default to real=false when uncertain.
FINDING: ${JSON.stringify(f)}
Steps:
1. Open ${ROOT}/${f.file} and confirm the cited code exists and actually exhibits the described problem (line numbers may be off by a few lines — judge the substance, search the file if needed).
2. Read ${ROOT}/AGENTS.md and check whether the flagged pattern is explicitly mandated or endorsed there, or is the dominant deliberate convention of the surrounding module (per the repository-conventions principle). If so set conventionEndorsed=true.
3. Judge whether the suggestion would genuinely improve clarity for a maintainer WITHOUT violating AGENTS.md. A finding that is technically true but whose fix makes the code read unlike the rest of the repo is NOT real.
4. Set adjustedSeverity honestly (low = cosmetic clarity, medium = actively misleads readers or breeds bugs, high = has likely already bred a bug or blocks safe modification).
Read-only. Output via StructuredOutput only.`;
}

function traceVerifyPrompt(f) {
  return `You are an adversarial verifier for ONE data-integrity finding in the MuseAmp repo (root: ${ROOT}). Lens: CORRECTNESS TRACE. Your job is to REFUTE it. Default to real=false when uncertain.
FINDING: ${JSON.stringify(f)}
Trace the exact failure scenario through the actual code: open ${ROOT}/${f.file} and every file on the claimed path, follow the calls, and decide whether the described sequence of events can actually occur and actually produces data loss / corruption / inconsistent state. Check for guards, callers that pre-validate, error handling that recovers, or invariants that make the scenario impossible. real=true ONLY if you can articulate the concrete reproduction path yourself. Read-only. StructuredOutput only.`;
}

function impactVerifyPrompt(f) {
  return `You are an adversarial verifier for ONE data-integrity finding in the MuseAmp repo (root: ${ROOT}). Lens: IMPACT AND BLAST RADIUS. Default to real=false when uncertain.
FINDING: ${JSON.stringify(f)}
Independently from whether the trace holds, evaluate: if this scenario occurs, what is actually damaged (user files? database rows? caches? recoverable on next rebuild?), how likely are the preconditions in normal usage, and is the damage user-visible or self-healing? Open the relevant files (${ROOT}/${f.file} and neighbors) to ground your judgment. real=false if the scenario, even when it occurs, is self-healing or has no durable effect (then explain why). adjustedSeverity: high = durable user-visible data loss/corruption, medium = inconsistent state needing manual repair (e.g. settings rebuild), low = transient/self-healing. Read-only. StructuredOutput only.`;
}

function normalizeTitle(t) {
  return String(t || "")
    .toLowerCase()
    .replace(/[^a-z0-9一-鿿]+/g, " ")
    .trim();
}

function dedupKey(f) {
  return `${f.file}|${normalizeTitle(f.title)}`;
}

function shortLabel(f) {
  const parts = String(f.file || "").split("/");
  return parts[parts.length - 1] || "finding";
}

async function verifyOne(f) {
  if (f.kind === "clarity") {
    const v = await agent(clarityVerifyPrompt(f), {
      label: `verify:${shortLabel(f)}`,
      phase: "Verify",
      schema: VERDICT_SCHEMA,
    });
    if (!v) return null;
    return {
      ...f,
      verdictReal: v.real === true,
      conventionEndorsed: v.conventionEndorsed === true,
      severity: v.adjustedSeverity || f.severity,
      verdictReasoning: v.reasoning,
    };
  }
  const votes = await parallel([
    () =>
      agent(traceVerifyPrompt(f), {
        label: `verify-trace:${shortLabel(f)}`,
        phase: "Verify",
        schema: VERDICT_SCHEMA,
      }),
    () =>
      agent(impactVerifyPrompt(f), {
        label: `verify-impact:${shortLabel(f)}`,
        phase: "Verify",
        schema: VERDICT_SCHEMA,
      }),
  ]);
  const ok = votes.filter(Boolean);
  if (!ok.length) return null;
  const real = ok.every((v) => v.real === true);
  const sevRank = { low: 0, medium: 1, high: 2 };
  let severity = f.severity;
  for (const v of ok) {
    if (v.adjustedSeverity && sevRank[v.adjustedSeverity] < sevRank[severity])
      severity = v.adjustedSeverity;
  }
  return {
    ...f,
    verdictReal: real,
    conventionEndorsed: false,
    severity,
    verdictReasoning: ok.map((v) => v.reasoning).join(" || "),
  };
}

// ---- Phase: Understand ----
phase("Understand");
log(`Mapping ${SCOPES.length} scopes in parallel`);
const maps = await parallel(
  SCOPES.map(
    (s) => () =>
      agent(mapPrompt(s), {
        label: `map:${s.key}`,
        phase: "Understand",
        schema: MAP_SCHEMA,
      }),
  ),
);
const mapByKey = {};
SCOPES.forEach((s, i) => {
  if (maps[i]) mapByKey[s.key] = maps[i];
});
log(`Scope maps ready: ${Object.keys(mapByKey).length}/${SCOPES.length}`);

// ---- Review loop (loop-until-dry) ----
const seen = new Set();
const allRecorded = []; // every deduped finding ever surfaced (for round>1 prompts)
const confirmed = [];
const rejected = [];
let round = 0;
let dry = 0;

while (dry < 2 && round < MAX_ROUNDS) {
  round += 1;
  const finderSpecs = [];
  for (const s of SCOPES)
    finderSpecs.push({ kind: "clarity", key: s.key, scope: s });
  for (const d of INTEGRITY) {
    if (d.key === "rebuild-validation-gap" && round > 1) continue; // one-shot feature-gap audit
    finderSpecs.push({ kind: "integrity", key: d.key, dim: d });
  }
  if (round === 1) {
    finderSpecs.push({
      kind: "clarity",
      key: "cross-target-duplication",
      cross: true,
    });
    finderSpecs.push({
      kind: "clarity",
      key: "docs-structure-sync",
      cross: true,
    });
  }
  log(
    `Round ${round}: launching ${finderSpecs.length} finders (dry streak: ${dry})`,
  );

  let freshThisRound = 0;
  const roundResults = await pipeline(
    finderSpecs,
    (spec) => {
      const prompt = spec.cross
        ? crossCuttingPrompt(spec.key, round)
        : spec.kind === "clarity"
          ? clarityPrompt(spec.scope, mapByKey[spec.key], round)
          : integrityPrompt(spec.dim, round);
      return agent(prompt, {
        label: `${spec.kind}:${spec.key}:r${round}`,
        phase: "Review",
        schema: FINDINGS_SCHEMA,
      });
    },
    (res, spec) => {
      if (!res || !Array.isArray(res.findings)) return [];
      const fresh = [];
      for (const raw of res.findings) {
        const f = { ...raw, kind: spec.kind, finder: spec.key, round };
        const k = dedupKey(f);
        if (seen.has(k)) continue;
        seen.add(k);
        allRecorded.push(f);
        fresh.push(f);
      }
      freshThisRound += fresh.length;
      if (fresh.length)
        log(
          `Round ${round} ${spec.kind}:${spec.key} → ${fresh.length} fresh findings, verifying`,
        );
      return fresh;
    },
    (fresh) => parallel(fresh.map((f) => () => verifyOne(f))),
  );

  const verified = roundResults.filter(Boolean).flat().filter(Boolean);
  let confirmedThisRound = 0;
  for (const v of verified) {
    if (v.verdictReal && !v.conventionEndorsed) {
      confirmed.push(v);
      confirmedThisRound += 1;
    } else rejected.push(v);
  }
  if (freshThisRound === 0) dry += 1;
  else dry = 0;
  log(
    `Round ${round} done: ${freshThisRound} fresh, ${confirmedThisRound} confirmed, ${verified.length - confirmedThisRound} refuted. Totals: ${confirmed.length} confirmed / ${rejected.length} refuted.`,
  );
}
if (round >= MAX_ROUNDS && dry < 2) {
  log(
    `NOTE: stopped at the ${MAX_ROUNDS}-round cap before reaching 2 consecutive dry rounds — coverage is broad but the tail may not be fully exhausted.`,
  );
}

// ---- Phase: Critique ----
phase("Critique");
const critic = await agent(
  `You are a completeness critic for a finished multi-agent review of the MuseAmp repo (root: ${ROOT}).
The review ran ${round} rounds over these clarity scopes: ${SCOPES.map((s) => s.key).join(", ")} and these integrity dimensions: ${INTEGRITY.map((d) => d.key).join(", ")}.
CONFIRMED FINDINGS (${confirmed.length}):
${confirmed.map((c) => `- [${c.kind}/${c.severity}] ${c.file}${c.line ? ":" + c.line : ""} — ${c.title}`).join("\n") || "(none)"}
REFUTED: ${rejected.length} findings were killed by adversarial verification.
TASK: Identify what is MISSING, not re-litigate what was found. Spot-check the repo yourself (read-only): are there directories/files no scope covered (check the repo tree against the scope paths: ${SCOPES.map((s) => s.paths.join("+")).join(" | ")})? Integrity angles nobody audited (e.g. localization xcstrings hygiene, Makefile/scripts, notification contract drift, test coverage of the audited flows)? Confirmed findings that look suspiciously thin for their area? List concrete gaps. StructuredOutput only.`,
  { label: "completeness-critic", phase: "Critique", schema: CRITIQUE_SCHEMA },
);

return {
  rounds: round,
  dryStreakAtEnd: dry,
  totalSurfaced: allRecorded.length,
  confirmedCount: confirmed.length,
  refutedCount: rejected.length,
  confirmed,
  refuted: rejected.map((r) => ({
    kind: r.kind,
    file: r.file,
    line: r.line,
    title: r.title,
    reason: r.verdictReasoning,
  })),
  critique: critic,
  scopeSummaries: SCOPES.map((s) => ({
    scope: s.key,
    summary: mapByKey[s.key] ? mapByKey[s.key].summary : "(mapping failed)",
  })),
};
