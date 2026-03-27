# Go Code Indexer CLI Implementation

## Goal

Build a small Go CLI that handles the CPU-heavy code parsing work for Code Intelligence, while Rails remains the system of record and owns orchestration, persistence, cross-repository search, product logic, and delivery.

This document defines:

- what the Go CLI should do
- what Rails should do
- the contract between them
- what to ship first

---

## High-Level Architecture

```text
Rails job/service
  -> prepares repo checkout + file list
  -> invokes Go CLI once per repository
  -> reads JSON output
  -> stores chunks / metadata / hashes / commit data
  -> runs embeddings + retrieval indexing
  -> searches and ranks across all repositories in the workspace

Go CLI
  -> walks files or accepts explicit file list
  -> detects language
  -> parses source with tree-sitter
  -> extracts semantic chunks + symbols + line ranges
  -> computes file/content hashes
  -> emits structured JSON
```

Core rule:

- Go owns parsing and extraction for a single repository checkout
- Rails owns workflow, storage, and workspace-wide multi-repo intelligence

Another core rule:

- the CLI should stay simple and deterministic
- ranking, confidence, and cross-repository interpretation belong in Rails

---

## Why Go CLI

Use Go as a CLI instead of a long-running service because it:

- keeps deployment simple
- integrates cleanly with Rails jobs
- is easy to version
- avoids introducing another always-on system
- is fast and memory-efficient for concurrent parsing

Do not move product logic into Go.

---

## Responsibilities

## Go CLI Responsibilities

The CLI should do only parsing/index preparation work.

### Required

- read a repo path
- optionally read an explicit file list
- detect supported languages
- skip unsupported / ignored files
- parse files using tree-sitter
- extract chunks
- extract symbol metadata where feasible
- compute content hashes
- output deterministic JSON

### Optional in later iterations

- extract high-confidence relationships like `contains`
- emit imports / inheritance metadata
- emit parse warnings
- emit file-level summary stats

### Explicitly out of scope for Go

- database writes
- embeddings API calls
- Slack/API delivery
- workspace auth / billing / quotas
- commit ingestion from provider APIs
- LLM reasoning

## Rails Responsibilities

Rails remains the orchestration layer and the workspace-wide intelligence layer.

### Required

- repository connection and auth
- clone/fetch repo locally
- choose files to parse
- choose which repositories participate in workspace analysis
- invoke CLI from jobs/services
- validate and ingest CLI output
- persist:
  - repositories
  - chunks
  - commit metadata
  - analysis records
- run embeddings
- run retrieval and ranking across repositories
- run incident analysis
- post results to Slack / UI / API

### Rails should also own

- workspace isolation
- retry logic
- quota enforcement
- indexing state
- error tracking and observability

---

## V1 Scope

The first version of the CLI should support:

- file-level parsing
- class / module extraction
- method / function extraction
- line ranges
- file hash
- chunk hash
- language detection
- graceful fallback when semantic extraction is weak

Do not block V1 on:

- call graph extraction
- deep symbol resolution
- cross-file relationship resolution
- imports/inheritance if they are noisy

---

## Supported Language Strategy

Use broad parsing support, but with quality tiers.

### Tier 1

Tune heavily first:

- Ruby
- TypeScript
- JavaScript

### Tier 2

Support early with simpler extraction:

- Python
- Go
- Java

### Tier 3

Fallback mode:

- file-level chunks only when semantic extraction is weak or parser quality is insufficient

This avoids artificial product limits while keeping the implementation honest.

---

## CLI Commands

Start with one command.

## `scan`

Scans a single repository or file subset and emits parsing results as JSON.

### Example

```bash
code-indexer scan \
  --repo-path /tmp/firefight-repos/123 \
  --files-json /tmp/firefight-repos/123/changed_files.json \
  --format json
```

### Required flags

- `--repo-path` absolute path to checked-out repository

### Optional flags

- `--files-json` JSON file containing explicit relative file paths to scan
- `--format` default `json`
- `--max-file-bytes` skip oversized files
- `--include-hidden` off by default
- `--languages` comma-separated allowlist

### Exit codes

- `0` success
- `1` fatal usage/config error
- `2` partial success with parse failures

Rails should treat `2` as ingestible if output JSON is still valid.

---

## JSON Output Contract

The CLI should emit one machine-readable JSON document to stdout.

### Top-level shape

```json
{
  "repoPath": "/tmp/firefight-repos/123",
  "scannedAt": "2026-03-27T12:00:00Z",
  "files": [
    {
      "path": "app/services/incident_lifecycle_service.rb",
      "language": "ruby",
      "status": "parsed",
      "fileHash": "sha256:...",
      "bytes": 12345,
      "chunks": [
        {
          "chunkType": "class",
          "name": "IncidentLifecycleService",
          "qualifiedName": "IncidentLifecycleService",
          "startLine": 1,
          "endLine": 120,
          "content": "class IncidentLifecycleService ...",
          "contentHash": "sha256:...",
          "parentQualifiedName": null
        },
        {
          "chunkType": "method",
          "name": "create",
          "qualifiedName": "IncidentLifecycleService#create",
          "startLine": 10,
          "endLine": 35,
          "content": "def create(...) ... end",
          "contentHash": "sha256:...",
          "parentQualifiedName": "IncidentLifecycleService"
        }
      ],
      "errors": []
    }
  ],
  "stats": {
    "filesSeen": 100,
    "filesParsed": 92,
    "filesSkipped": 8,
    "chunksExtracted": 480,
    "parseErrors": 3
  }
}
```

## File object

Required fields:

- `path`
- `language`
- `status` (`parsed`, `skipped`, `unsupported`, `error`)
- `fileHash`
- `bytes`
- `chunks`
- `errors`

## Chunk object

Required fields:

- `chunkType` (`file`, `class`, `module`, `method`, `function`)
- `name`
- `qualifiedName`
- `startLine`
- `endLine`
- `content`
- `contentHash`

Optional fields:

- `parentQualifiedName`
- `metadata`

Important:

- line numbers must be 1-based
- file paths must be repo-relative
- JSON output must be deterministic for the same input

---

## File Selection Rules

Rails decides what to scan.

The Go CLI should support both:

- full-repo walk
- explicit file subset

### Ignore by default

- `.git/`
- `node_modules/`
- `vendor/`
- `tmp/`
- `log/`
- `storage/`
- `dist/`
- `build/`
- coverage artifacts
- minified files
- binaries
- lockfiles
- generated assets

### Skip conditions

- file exceeds size threshold
- unsupported extension
- binary content detected
- parse failure severe enough to prevent chunk extraction

Skipped files should still be represented in output with a reason.

---

## Parsing and Chunking Rules

### General rules

- prefer fewer, higher-signal chunks
- preserve exact source content for each chunk
- emit file-level fallback chunk when semantic extraction fails
- avoid tiny fragments with poor retrieval value

### V1 chunk types

- `file`
- `class`
- `module`
- `method`
- `function`

### V1 extraction strategy

- extract top-level file chunk if useful
- extract class/module definitions
- extract method/function definitions
- if nested structure is clear, emit `parentQualifiedName`

### Do not do in V1

- local variable blocks
- arbitrary AST node chunks
- fuzzy call graph edges
- language-specific deep data-flow analysis

---

## Hashing Rules

Hashes are critical for cost control.

### File hash

- based on raw file contents
- used to detect unchanged files

### Chunk hash

- based on raw chunk content
- used to skip re-embedding unchanged chunks

Use SHA-256 and prefix values consistently, e.g. `sha256:<hex>`.

---

## Error Handling

The CLI should be resilient.

### Principles

- one bad file should not fail the full scan
- partial results should still be usable
- errors should be structured, not just stderr noise

### File-level errors

Each file may include errors like:

```json
{
  "code": "parse_error",
  "message": "unexpected token near line 42"
}
```

### stderr usage

- human-readable logs only
- Rails should not depend on stderr for ingestion logic

---

## Suggested Go Project Structure

```text
code-indexer/
  cmd/
    code-indexer/
      main.go
  internal/
    cli/
    scan/
    detect/
    parser/
    chunker/
    output/
    ignore/
    hashing/
    languages/
  pkg/
    schema/
```

Suggested responsibilities:

- `detect/` file extension and content detection
- `ignore/` ignore rules
- `parser/` tree-sitter wrappers
- `chunker/` language-specific chunk extraction
- `output/` JSON serialization
- `schema/` shared structs for scan output

---

## Rails-Side Design

Rails should treat the CLI as a deterministic worker tool.

## Models

At minimum:

- `CodeRepository`
- `CodeChunk`
- `CodeCommit`
- `IncidentAnalysis`

Recommended repository metadata for multi-repo workspaces:

- `repo_kind` such as `service`, `library`, `frontend`, `infra`
- `service_name` when applicable
- `owned_by_team` when applicable
- optional dependency hints or adjacency metadata
- repository active/indexing status

### Dependency hints

These can start as simple manual metadata in Phase 1.

Examples:

- service A depends on library B
- frontend C depends on API D
- worker E consumes events from service F

Rails should use these hints only as ranking boosts, not as hard truth.

Recommended fields for `CodeChunk`:

- `code_repository_id`
- `file_path`
- `language`
- `chunk_type`
- `name`
- `qualified_name`
- `parent_qualified_name`
- `content`
- `content_hash`
- `file_hash`
- `start_line`
- `end_line`
- `commit_sha`
- `indexed_at`
- `embedding`

## Rails Jobs / Services

### `CodeIndexJob`

Responsibilities:

- ensure repo checkout exists
- compute file set to scan
- invoke CLI
- parse CLI output
- upsert file/chunk rows
- enqueue embedding work if needed
- update repository indexing state

Important:

- one indexing run is still repository-scoped
- Rails handles multi-repo orchestration by invoking the CLI separately per repository

### `CodeIndexService`

Responsibilities:

- orchestrate one indexing run
- manage full vs incremental behavior
- delete removed-file chunks
- skip unchanged files using hashes

### `CodeIndexerCli`

Create a thin Ruby wrapper object around CLI execution.

Responsibilities:

- build command
- run command safely
- capture stdout/stderr/exit code
- parse JSON
- surface structured errors

### `CodeEmbeddingJob`

Responsibilities:

- embed only changed/new chunks
- batch requests
- respect quotas and rate limits

### `CodeSearchService`

Responsibilities:

- direct file/path lookup
- vector search across all indexed repositories in the workspace
- merge/rank results across repositories
- use repository metadata and dependency hints in ranking when available

### Ranking Strategy In Rails

Phase 1 ranking should be explicit and simple.

Recommended order of influence:

1. stack trace direct path matches
2. exact file path matches from incident context
3. semantic similarity score
4. repository dependency-hint boosts
5. repository classification/context boosts
6. recent commits touching top-ranked files

This must be implemented in Rails, not in the CLI.

### `CodeAnalysisService`

Responsibilities:

- assemble incident context + retrieved code + commits
- assemble candidate repositories involved in the incident
- call model
- store result
- return formatted analysis

---

## Rails -> CLI Contract

Rails should call the CLI with a repo path and, when possible, a constrained file list.

For multi-repo workspaces, Rails repeats this per repository.

Rails should never expect the CLI to understand workspace-level context.

### Example Ruby wrapper behavior

```ruby
result = CodeIndexerCli.scan(
  repo_path: repo.checkout_path,
  files: changed_files,
  max_file_bytes: 300_000
)
```

Rails then:

- validates output shape
- stores per-file parse status
- upserts chunks
- marks stale chunks deleted when files are removed

---

## Incremental Indexing Flow

### Full index

1. Rails connects repository
2. Rails clones/fetches repo
3. Rails invokes CLI over full supported file set
4. Rails stores chunks and queues embeddings
5. Rails stores `last_indexed_sha`

Workspace-wide initial enablement means repeating this for each connected repository.

If some repositories fail indexing, Rails should still persist successful repository results and mark failed repositories clearly.

### Incremental index

1. Push webhook arrives for a repository
2. Rails determines changed/deleted files for that repository
3. Rails invokes CLI only for changed files
4. Rails deletes chunks for removed files
5. Rails updates changed chunks only
6. Rails embeds only new/changed chunk hashes
7. Rails updates `last_indexed_sha`

If `last_indexed_sha` becomes invalid after a force-push or history rewrite, Rails should fall back to a safe re-index strategy for that repository.

---

## Partial Coverage Behavior

Workspace analysis must proceed even when repository coverage is incomplete.

Rails should track per-repository status such as:

- indexed
- stale
- indexing
- failed
- paused

Analysis results should include coverage metadata, for example:

- repositories searched
- repositories skipped
- repositories stale or failed

Confidence should be reduced when likely-relevant repositories are stale or unavailable.

---

## Cost Control Requirements

These should be enforced on the Rails side.

### Required controls

- max repositories per workspace in V1
- max file size
- max chunks per run
- max files per run
- workspace-level monthly indexing quota
- content-hash dedupe before embedding
- incremental indexing only after initial scan

### Recommended controls

- pause indexing when quota exceeded
- record estimated embedding cost per run
- expose indexing stats in admin/debug UI

### Multi-repo controls

- max repositories per workspace in Phase 1
- max concurrent indexing jobs per workspace
- workspace-level monthly embedding budget across all repositories

---

## Security and Storage

### Repository checkout storage

- Rails should manage checkout paths
- each repository checkout should be isolated
- cleanup/retention policy should be explicit

### CLI trust boundary

- the CLI should read local repository contents and emit JSON only
- it should not talk directly to the database or external model providers

### Data minimization

- Rails should send only needed chunks/snippets to models
- raw repository contents should not be forwarded wholesale to LLMs

### Workspace isolation

- repository metadata, chunks, embeddings, commits, and analyses must be scoped to a workspace
- search queries must never cross workspace boundaries

---

## Concurrency and Locking

### Repository lock

- only one active indexing run per repository

### Workspace behavior

- indexing one repository should not block analysis across the entire workspace
- analysis should use the latest successful repository indexes

### Idempotent ingestion

- ingesting the same scan result twice should be safe
- unchanged file and chunk hashes should not generate duplicate embeddings or duplicate logical rows

### Webhook coalescing

- repeated push events for the same repository should be coalesced or superseded where possible

---

## Observability

### Go CLI should emit

- summary stats in JSON
- file-level error counts
- optional timing metrics in stderr logs

### Rails should record

- scan duration
- files processed
- chunks extracted
- parse failures
- embedding counts
- embedding cost estimate
- indexing job success/failure

---

## Testing Strategy

## Go CLI tests

- language detection tests
- ignore rule tests
- per-language chunk extraction fixtures
- stable JSON output tests
- partial failure behavior tests

## Rails tests

- CLI wrapper tests
- indexing service tests with fixture JSON
- incremental update tests
- chunk dedupe tests
- embedding enqueue tests
- analysis pipeline tests

Important:

- Rails tests should not require the real Go binary for most service tests
- use fixture JSON outputs for ingestion tests

---

## Phase-by-Phase Delivery

## Phase 1

Build the minimum viable parser contract.

### Go

- `scan` command
- file detection + ignore rules
- Ruby/TS/JS tuned extraction
- broad fallback support for other languages
- JSON output contract
- file/chunk hashing

### Rails

- `CodeRepository`, `CodeChunk`, `CodeCommit`, `IncidentAnalysis`
- `CodeIndexerCli` wrapper
- `CodeIndexJob` + `CodeIndexService`
- incremental file-based indexing
- embeddings for changed chunks
- `/ff analyze`
- workspace-wide multi-repo search and ranking

## Phase 2

Improve precision.

### Go

- cleaner qualified names
- parent/contains metadata
- better per-language chunk extraction

### Rails

- better ranking
- snippet retrieval with line ranges
- stronger commit correlation
- stronger cross-repository ranking using repo metadata and dependency hints

## Phase 3

Support fix suggestions.

### Go

- no major expansion required unless additional structural metadata helps ranking

### Rails

- richer context assembly
- diff-aware analysis
- suggested fix plans
- confidence/risk output
- better microservice/shared-library root-cause attribution

---

## Non-Goals

Do not do these in the first implementation:

- long-running Go indexing service
- DB writes from Go
- embedding calls from Go
- full graph engine
- precise cross-language call graph resolution
- autonomous code mutation

---

## Final Recommendation

Build a small Go CLI focused on parsing and chunk extraction.

Keep Rails responsible for:

- orchestration
- persistence
- embeddings
- retrieval
- analysis
- delivery

That gives Firefight a fast indexing engine without fragmenting core application logic across two systems.

Multi-repo awareness should live primarily in Rails, not in the CLI:

- the CLI stays repo-scoped
- Rails searches and ranks across all workspace repositories
- this keeps the parsing engine simple while enabling microservice and shared-library incident analysis
