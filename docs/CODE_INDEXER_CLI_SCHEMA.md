# Code Indexer CLI JSON Schema Contract

## Goal

Define the strict JSON contract emitted by the Go `code-indexer` CLI so Rails can ingest results safely and deterministically.

This is a contract document, not an implementation guide.

---

## Command

Primary command:

```bash
code-indexer scan --repo-path /path/to/repo --format json
```

The CLI must emit exactly one JSON document to stdout.

stderr is allowed for human-readable logs only.

---

## Top-Level JSON Shape

```json
{
  "schemaVersion": "1.0",
  "repoPath": "/tmp/firefight-repos/123",
  "scannedAt": "2026-03-27T12:00:00Z",
  "files": [],
  "stats": {
    "filesSeen": 0,
    "filesParsed": 0,
    "filesSkipped": 0,
    "filesErrored": 0,
    "chunksExtracted": 0,
    "parseErrors": 0
  }
}
```

## Required top-level fields

- `schemaVersion` string
- `repoPath` string
- `scannedAt` string, ISO8601 UTC timestamp
- `files` array
- `stats` object

---

## File Object

Each scanned file must produce one file object.

### Shape

```json
{
  "path": "app/services/incident_lifecycle_service.rb",
  "language": "ruby",
  "status": "parsed",
  "fileHash": "sha256:abc123",
  "bytes": 12345,
  "chunks": [],
  "errors": []
}
```

### Required fields

- `path` string, repo-relative
- `language` string
- `status` enum
- `fileHash` string
- `bytes` integer
- `chunks` array
- `errors` array

### `status` values

- `parsed`
- `skipped`
- `unsupported`
- `error`

### Rules

- `path` must use forward slashes
- `path` must be repo-relative
- `bytes` must be non-negative
- `fileHash` must be stable for identical file contents
- `chunks` may be empty
- `errors` may be empty

### Behavior by status

#### `parsed`

- `chunks` may contain one or more chunks
- `errors` may still contain non-fatal warnings/errors

#### `skipped`

- `chunks` must be empty
- `errors` should include a structured reason

#### `unsupported`

- `chunks` must be empty
- `errors` should include a structured reason

#### `error`

- `chunks` may be empty or may contain partial fallback chunks if safe
- `errors` must include at least one structured error

---

## Chunk Object

Each chunk represents a searchable code unit.

### Shape

```json
{
  "chunkType": "method",
  "name": "create",
  "qualifiedName": "IncidentLifecycleService#create",
  "parentQualifiedName": "IncidentLifecycleService",
  "startLine": 10,
  "endLine": 35,
  "content": "def create(...)\n  ...\nend",
  "contentHash": "sha256:def456",
  "metadata": {}
}
```

### Required fields

- `chunkType` string
- `name` string or `null`
- `qualifiedName` string or `null`
- `startLine` integer
- `endLine` integer
- `content` string
- `contentHash` string

### Optional fields

- `parentQualifiedName` string or `null`
- `metadata` object

### Allowed `chunkType` values in Phase 1

- `file`
- `class`
- `module`
- `method`
- `function`

### Rules

- line numbers are 1-based
- `startLine <= endLine`
- `content` must match the actual source slice represented by the chunk
- `contentHash` must be stable for identical chunk content
- `qualifiedName` may be null in fallback cases
- `name` may be null for coarse fallback file chunks

---

## Error Object

Errors must be structured.

### Shape

```json
{
  "code": "parse_error",
  "message": "unexpected token near line 42"
}
```

### Required fields

- `code` string
- `message` string

### Suggested `code` values

- `parse_error`
- `unsupported_language`
- `binary_file`
- `file_too_large`
- `ignored_path`
- `read_error`

---

## Stats Object

### Shape

```json
{
  "filesSeen": 100,
  "filesParsed": 92,
  "filesSkipped": 5,
  "filesErrored": 3,
  "chunksExtracted": 480,
  "parseErrors": 3
}
```

### Required fields

- `filesSeen` integer
- `filesParsed` integer
- `filesSkipped` integer
- `filesErrored` integer
- `chunksExtracted` integer
- `parseErrors` integer

### Rules

- all values must be non-negative
- counts should be internally consistent

---

## Fallback Behavior

If semantic extraction is weak but file reading succeeded:

- emit a `parsed` file object
- include a coarse `file` chunk
- set `name` / `qualifiedName` to null if needed
- preserve full file line span

This allows retrieval without pretending semantic precision exists.

---

## Determinism Requirements

For the same repository contents and CLI version:

- file ordering must be deterministic
- chunk ordering within a file must be deterministic
- hashes must be deterministic
- repeated runs must emit semantically identical JSON

This is important for Rails ingestion, diffing, and test fixtures.

---

## Rails Validation Expectations

Rails should reject or flag output when:

- required fields are missing
- file paths are not repo-relative
- line ranges are invalid
- stats are malformed
- JSON is invalid

Rails should tolerate:

- partial file failures
- parsed files with warnings
- mixed statuses within the same scan result

---

## Exit Code Expectations

- `0` success
- `1` fatal usage/config/runtime error with no reliable output
- `2` partial success with valid JSON output and one or more file-level failures

Rails should ingest valid stdout JSON when exit code is `2`.

---

## Versioning Rules

- `schemaVersion` must be present from the first release
- breaking JSON changes must bump the schema version
- Rails should gate parsing logic by known schema versions if needed

Recommended initial version:

- `1.0`

---

## Phase 1 Non-Goals For The Schema

Do not require these yet:

- call graph edges
- cross-file symbol resolution
- import graph completeness
- inheritance graph completeness
- language-specific semantic metadata beyond what is reliable

Those can be added later through optional fields or a future schema version.
