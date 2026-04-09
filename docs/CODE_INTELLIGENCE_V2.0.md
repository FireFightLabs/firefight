# Code Intelligence V2.0

## Goal

Build a useful first version of code intelligence that:

- works across common languages
- works across multi-repo workspaces
- keeps costs controlled
- returns relevant code and suspect commits for incidents
- evolves into snippet-level diagnosis and fix suggestions

## Product Principle

- Broad parsing support from day one
- High-confidence retrieval tuned first for the languages we see most and can validate well
- Do not block indexing on perfect semantic understanding

This means V1 is not "Ruby + TS/JS only."

It means:

- index many languages
- optimize retrieval quality iteratively
- gracefully fall back to coarser indexing when language-specific semantics are weaker

Two important implementation principles:

- workspace intelligence is broad from the start
- parser sophistication and ranking quality improve incrementally over time

This means a workspace may support many repositories and many languages in Phase 1, even if snippet precision is materially better for some languages than others.

---

## Related Docs

- Implementation boundary and Go CLI plan: `docs/CODE_INDEXER_CLI_IMPLEMENTATION.md`
- Strict Go CLI JSON contract: `docs/CODE_INDEXER_CLI_SCHEMA.md`
- Rails Phase 1 models/jobs/services plan: `docs/CODE_INTELLIGENCE_PHASE1_RAILS_PLAN.md`
- Ranking formulas and scoring examples: `docs/CODE_INTELLIGENCE_RANKING.md`
- Private/public architecture boundary: `docs/CODE_INTELLIGENCE_PRIVATE_BOUNDARY.md`
- Deprecated earlier plan: `docs/CODE_INTELLIGENCE_DEPRECATED.md`

## Prior Art

- **Codesight** (https://github.com/Houseofmvps/codesight): AI-optimized codebase documentation generator. Key ideas borrowed: blast radius analysis via import dependency graphs, structural summary as fast context layer for AI agents, explicit route and schema extraction as first-class indexed artifacts. Codesight is a static CLI tool for single repos — our system extends these ideas to multi-repo, semantic search, and incident-time correlation.

---

## Core Data Model

At minimum, the system should use:

### `code_repositories`

One row per connected repository.

Recommended fields:

- `workspace_id`
- `provider`
- `owner`
- `name`
- `default_branch`
- `last_indexed_sha`
- `indexed_at`
- `status` (`pending`, `indexing`, `indexed`, `failed`, `paused`)
- `repo_kind` (`service`, `library`, `frontend`, `infra`)
- `service_name` (optional)
- `owned_by_team` (optional)
- `dependency_hints` (jsonb, optional)
- `structural_summary` (jsonb, optional) — pre-computed structural map generated during indexing: routes, schema models, key modules, entry points, environment variables. ~3-5K tokens when serialized. Used by `get_structural_summary` tool to orient the AI agent before exploration begins. Inspired by [Codesight](https://github.com/Houseofmvps/codesight).

### `code_chunks`

Searchable units of code.

Recommended fields:

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

### `code_import_graph`

File-level import/dependency edges. Used for blast radius analysis — "if this file changes, what breaks downstream?"

Recommended fields:

- `code_repository_id`
- `source_path` (the file that imports)
- `target_path` (the file being imported)
- `import_type` (`import`, `require`, `include`, `extend`, `use`)

Built during indexing via AST analysis. The `get_blast_radius` tool traverses this graph transitively (1-3 hops) from a given file to find all affected routes, models, and modules. Cross-repo edges are supported via `dependency_hints` on `code_repositories`.

Inspired by [Codesight's](https://github.com/Houseofmvps/codesight) dependency graph and blast radius analysis.

### `code_commits`

Recent commit history for ranking and change correlation.

Recommended fields:

- `code_repository_id`
- `sha`
- `message`
- `author`
- `committed_at`
- `files_changed`
- `diff_summary`

### `incident_analyses`

Stored analysis results.

Recommended fields:

- `incident_id`
- `query_context`
- `coverage_summary`
- `relevant_chunks`
- `suspect_commits`
- `suspect_repositories`
- `confidence_score`
- `explanation`
- `suggested_fix`
- `recommended_next_checks`
- `model_used`
- `analyzed_at`

---

## Architecture Direction

Implementation posture:

- start inside the Rails application
- keep ingress thin and async
- isolate code intelligence behind dedicated service boundaries
- extract into a separate service later only if load, ownership, or privacy requirements justify it

This keeps product velocity high now while preserving a clean path to a dedicated service in the future.

### Core Flow

```text
Repositories connected to workspace
  -> CodeIndexJob
    -> clone/fetch repository
    -> tree-sitter parse
    -> semantic chunk extraction
    -> embeddings / retrieval index
    -> commit ingestion
    -> store searchable code data per repository

User runs /ff analyze or analysis is requested
  -> AnalyzeIncidentCodeJob
    -> CodeAnalysisAgent (tool-use loop)
      -> agent receives incident context (error, stack trace, affected service)
      -> agent iteratively calls tools to explore the code index
      -> agent follows leads, backtracks, cross-references
      -> agent builds diagnosis from accumulated evidence
    -> persist IncidentAnalysis
    -> post result to incident channel
```

### Analysis Agent: Tool-Use Over RAG

Traditional RAG retrieves a fixed set of top-K chunks and stuffs them into a context window. This fails when the answer spans multiple files, when the relevant code isn't semantically similar to the query, or when the agent needs to follow a call chain across services.

Instead, the analysis agent explores the code index interactively using tools — the same way a human engineer debugs an incident. The agent starts with incident context and iteratively calls tools to search, read, traverse, and correlate.

Inspired by [Mintlify's virtual filesystem approach](https://www.mintlify.com/blog/how-we-built-a-virtual-filesystem-for-our-assistant) where they replaced RAG with filesystem-style tools over their indexed documentation. The key insight: agents are better at exploring than consuming bulk context.

#### Available Tools

The analysis agent has access to these tools against the code index:

| Tool | Description | Backed by |
|------|-------------|-----------|
| `search_code(query, language?, repo?)` | Semantic search over code chunks | pgvector similarity on `code_chunks.embedding` |
| `grep_exact(pattern, repo?, path_filter?)` | Exact string/regex match in indexed code | Direct query on `code_chunks.content` |
| `read_file(repo, path)` | Full file content reconstructed from chunks | `code_chunks` ordered by `start_line` |
| `list_files(repo, directory?)` | Directory listing from indexed paths | Distinct `file_path` prefix query on `code_chunks` |
| `get_recent_commits(repo?, path?, since?)` | Commits touching a file/directory | `code_commits` filtered by `files_changed` |
| `get_chunk_relationships(chunk_id)` | Callers, callees, imports, inheritance | `chunk_relationships` graph traversal |
| `get_repo_info(repo?)` | Repository metadata, index status, classification | `code_repositories` lookup |
| `get_structural_summary(repo)` | Pre-computed structural map: routes, schema, key modules, entry points (~3-5K tokens) | `code_repositories.structural_summary` (jsonb) |
| `get_blast_radius(repo, path)` | Files, routes, and models transitively affected by changes to a file | `code_import_graph` traversal |

#### How It Works

```text
1. Agent receives incident context:
   - error message / stack trace
   - affected service (from catalogue)
   - incident severity, type, timeline

2. Agent orients (structural summary — fast, cheap):
   - get_structural_summary() for affected service repo
   - Agent now knows: routes, schema, key modules, entry points (~3-5K tokens)
   - This replaces blind exploration — the agent starts with a map

3. Agent explores (iterative tool-use loop):
   - Parse stack trace → read_file() for each frame
   - grep_exact() for error strings across repos
   - search_code() for semantically related code
   - get_blast_radius() on suspect files to understand downstream impact
   - get_chunk_relationships() to follow call chains
   - get_recent_commits() on suspect files
   - list_files() to understand directory structure
   - Cross-reference findings across multiple repos

4. Agent synthesizes:
   - Accumulates evidence across tool calls
   - Identifies root cause with supporting code
   - Ranks suspect commits by relevance
   - Includes blast radius assessment (what else might be affected)
   - Produces structured diagnosis
```

#### Why Tool-Use Beats RAG Here

| Problem | RAG approach | Tool-use approach |
|---------|-------------|-------------------|
| Answer spans multiple files | Fails — top-K may miss related files | Agent follows leads file-to-file |
| Exact syntax needed (error string) | Embedding similarity misses exact matches | `grep_exact` finds it directly |
| Call chain crosses services | No way to traverse relationships | `get_chunk_relationships` + `read_file` |
| Need commit context | Separate retrieval, hard to correlate | Agent calls `get_recent_commits` on files it already identified |
| Irrelevant chunks in context | Wastes context window, confuses model | Agent only reads what it needs |
| Partial index coverage | Silent failure — missing repos not surfaced | Agent checks `get_repo_info`, reports gaps |

#### Coarse-Then-Fine Search Pattern

For `grep_exact` and `search_code`, use a two-phase pattern to keep queries fast:

1. **Coarse filter**: pgvector similarity or metadata query identifies which files/chunks might match
2. **Bulk prefetch**: load matching chunks into memory
3. **Fine filter**: exact match/regex against prefetched content

This avoids scanning every chunk in the database for every tool call.

#### Cost Control

The tool-use loop is more expensive per-analysis than single-shot RAG because it involves multiple LLM calls. Mitigations:

- Cap tool calls per analysis (e.g., max 20 tool calls)
- Use a cheaper model for exploration, stronger model for final synthesis
- Cache tool results within the same analysis session (repeated `read_file` for the same path returns cached content)
- Parallelize independent tool calls where possible (e.g., reading multiple stack trace files simultaneously)

### Support Tiers By Language

Instead of artificially limiting the product to a tiny language set, use support tiers:

#### Tier 1: Fully tuned

Languages we actively optimize and validate first.

Examples:

- Ruby
- TypeScript / JavaScript

Capabilities:

- semantic chunking
- stronger ranking
- better snippet selection
- best retrieval quality

#### Tier 2: Broad supported

Languages that are parsed and indexed with useful retrieval, but with simpler heuristics.

Examples:

- Python
- Go
- Java

Capabilities:

- file-level metadata
- semantic chunks where feasible
- vector retrieval
- lower-confidence structural enrichment

#### Tier 3: Fallback

Languages where tree-sitter parsing is available but semantic extraction is weaker or not yet tuned.

Capabilities:

- file-level indexing
- coarse chunking only
- basic retrieval without advanced semantic assumptions

This keeps the system broad without pretending every language is equally mature on day one.

### Fallback Policy

When semantic extraction quality is weak for a language or file:

- still index the file
- emit a coarse file-level chunk
- preserve path, language, file hash, and line span
- allow the file to participate in retrieval with lower confidence

This avoids false precision while preserving multi-language coverage.

---

## Phase 1 - Relevant Code + Suspect Commits

### Deliverable

A manual `/ff analyze` flow that:

- looks at incident context
- finds likely relevant code
- correlates recent commits
- returns a concise diagnosis with next checks

### What Phase 1 Includes

#### 1. Repository connection

- multi-repo per workspace from the start
- GitHub integration
- store per repository:
  - provider
  - owner
  - repo name
  - default branch
  - last indexed sha
  - indexed at
  - optional repo classification metadata such as:
    - `service`
    - `library`
    - `frontend`
    - `infra`
  - optional dependency hints to improve ranking in microservice/shared-library setups

#### 2. Broad language indexing

- use `tree-sitter` for supported source files
- parse common languages broadly
- extract:
  - file path
  - language
  - chunk type
  - chunk content
  - start/end line
  - symbol/name where feasible

#### 3. Chunking strategy

Use only high-value chunk types:

- file
- class / module
- method / function

Avoid tiny low-signal fragments in early versions.

If semantic extraction is weaker for a language, fall back to coarse chunks rather than failing.

#### 4. Storage

- `code_repositories` (including `structural_summary` jsonb)
- `code_chunks`
- `code_commits`
- `code_import_graph` (file-level import edges for blast radius)
- `incident_analyses`

`chunk_relationships` is optional in Phase 1 and should be limited to only very high-confidence relationships if included at all.

#### 4a. Structural summary generation

During indexing, generate a `structural_summary` for each repository. This is a pre-computed map stored as jsonb on `code_repositories`:

```json
{
  "routes": [
    { "method": "POST", "path": "/api/v1/incidents", "file": "app/controllers/api/v1/incidents_controller.rb", "dependencies": ["auth", "db"] },
    { "method": "GET", "path": "/dashboard", "file": "app/controllers/dashboard_controller.rb", "dependencies": ["db", "cache"] }
  ],
  "schema_models": [
    { "name": "Incident", "file": "app/models/incident.rb", "fields": ["name", "status", "severity", "channel_id"], "associations": ["has_many :incident_events", "belongs_to :workspace"] }
  ],
  "key_modules": [
    { "name": "IncidentLifecycleService", "file": "app/services/incident_lifecycle_service.rb", "description": "All incident write operations" }
  ],
  "entry_points": ["app/controllers/api/", "app/services/interactions/", "app/jobs/"],
  "env_vars": ["DATABASE_URL", "RAILS_MASTER_KEY", "SLACK_SIGNING_SECRET"]
}
```

This orients the AI agent before it starts exploring (~3-5K tokens). Without it, the agent wastes tool calls figuring out the repo structure. With it, the agent starts with a map.

Generated via AST extraction during indexing (route detection, schema parsing, import analysis). Regenerated on each full index. Inspired by [Codesight](https://github.com/Houseofmvps/codesight).

#### 4b. Import graph for blast radius

During indexing, extract file-level import/dependency edges into `code_import_graph`. For each file, record what it imports and what imports it.

The `get_blast_radius(repo, path)` tool traverses this graph transitively (1-3 hops downstream) to answer: "if this file changes or breaks, what routes, models, and services are affected?"

This is critical for incident diagnosis — the AI agent identifies a suspect file, then checks its blast radius to assess the scope of impact before recommending fixes.

Built from AST `import`/`require`/`include` statements. Cross-repo edges use `dependency_hints` on `code_repositories`.

#### 5. Incremental indexing

- initial full index on repo connect
- push webhook re-indexes only changed files
- deleted files remove associated chunks
- content hash dedupe prevents re-embedding unchanged chunks

#### 6. Commit ingestion

Store:

- sha
- message
- author
- committed_at
- changed file paths
- optional compact diff summary

#### 7. Retrieval tools

Phase 1 implements the tool-use analysis approach (see "Analysis Agent: Tool-Use Over RAG" above). The minimum tool set for Phase 1:

| Tool | Phase 1 scope |
|------|--------------|
| `search_code` | pgvector similarity search across all workspace repos |
| `grep_exact` | Exact string match on `code_chunks.content` |
| `read_file` | Reconstruct full file from ordered chunks |
| `list_files` | Distinct file paths from `code_chunks` |
| `get_recent_commits` | Filter `code_commits` by path and recency |
| `get_repo_info` | Repository metadata and index status |
| `get_structural_summary` | Pre-computed repo map: routes, schema, key modules (~3-5K tokens) |
| `get_blast_radius` | Transitive downstream impact from a file via `code_import_graph` |

`get_chunk_relationships` is deferred to Phase 2 (requires relationship extraction during indexing).

#### 8. Analysis agent

`CodeAnalysisAgent` runs as a tool-use loop:

1. Receives incident context (error message, stack trace, affected service, severity)
2. Iteratively calls retrieval tools to explore the code index
3. Synthesizes findings into a structured diagnosis

The agent replaces the previous static pipeline (`CodeSearchService` → `CodeAnalysisService`) with an interactive exploration pattern. This handles cross-file, cross-repo answers that single-shot RAG misses.

Returns:

- likely root cause
- likely affected repository or repositories
- relevant code areas with exact file paths and line ranges
- suspect commit(s)
- recommended next checks
- coverage summary (which repos were searched, any gaps)

#### 9. Delivery

- manual `/ff analyze`
- store result as `IncidentAnalysis`
- post analysis into the incident Slack channel

### What Phase 1 Does Not Include

- deep call graph resolution
- low-confidence `calls` edges as a dependency
- auto-analysis on every incident
- patch generation
- PR creation

### Cost Controls For Phase 1

- max repositories per workspace in V1
- skip vendored/generated/build artifacts
- skip oversized files
- incremental indexing only
- content-hash dedupe before embedding
- workspace-level indexing quotas
- cheap model stack for indexing
- stronger reasoning model only at incident-analysis time

### Partial Coverage Behavior

Phase 1 analysis must tolerate incomplete workspace coverage.

Examples:

- some repositories are not connected
- some repositories failed indexing
- only a subset of repositories are up to date

In those cases:

- analysis should still run
- results should include a coverage summary
- confidence should be reduced when likely-relevant repositories are missing or stale

Example output concept:

- "Analysis based on 4 of 6 connected repositories; 1 repository stale, 1 failed indexing"

---

## Phase 2 - Exact Snippets + Higher Precision

### Deliverable

Move from "likely files across likely repos" to "these exact methods/classes and line ranges are most relevant."

### What Phase 2 Adds

#### 1. Better ranking

Combine and weight:

- stack trace hits
- repository classification and dependency hints
- exact file path matches
- vector similarity
- symbol/name matches
- commit recency

#### 2. Exact snippet retrieval

For top-ranked chunks, return:

- file path
- start line
- end line
- exact snippet
- small surrounding context window

#### 3. Structural relationships

Introduce only high-confidence structural edges first:

- `contains`
- optionally `imports`
- optionally `inherits`

Do not depend on fuzzy `calls` edges yet.

#### 4. Better commit correlation

Improve ranking of suspect commits by:

- recency window
- overlap with candidate file paths
- overlap with top-ranked snippets

#### 5. Better incident output

Analysis result should now include:

- most relevant files
- most relevant repositories
- most relevant snippets
- most likely suspicious commit(s)
- confidence level
- recommended code areas to inspect first

### Partial Coverage In Phase 2

Phase 2 should continue to surface coverage explicitly, especially when showing exact snippets.

If snippet precision is only available for some repositories or languages, the output should say so rather than implying equal confidence everywhere.

### Outcome Of Phase 2

Responders should be able to see the actual code likely involved in the incident, including when the problem spans multiple services or shared library repositories.

---

## Phase 3 - Suggested Fix Plan

### Deliverable

Move from diagnosis to actionable remediation guidance.

### What Phase 3 Adds

#### 1. Richer context assembly

For the top-ranked candidate areas, include:

- surrounding source context
- relevant recent diffs
- deploy/change context if available
- incident summary and error signals
- workspace repo metadata and dependency hints

#### 2. Fix-plan generation

Analysis should return:

- likely root cause
- why the failure happened
- whether the issue likely originates in a service repo, shared library repo, or integration boundary
- exact code area to modify
- suggested implementation strategy
- risks or uncertainties

#### 3. Stronger output contract

Store and display structured results like:

- `confidence_score`
- `relevant_chunks`
- `suspect_commits`
- `explanation`
- `suggested_fix`
- `recommended_next_checks`

#### 4. Human-in-the-loop presentation

This phase should still present a proposed fix plan, not directly mutate code.

Examples:

- "Move retry rescue below timeout normalization"
- "Guard nil status before calling lifecycle transition"
- "Revert behavior introduced in commit abc123 or reintroduce fallback branch"

### What Phase 3 Still Does Not Include

- automatic patch application
- draft PR creation
- autonomous fixes in customer repos

### Outcome Of Phase 3

Responders get:

- relevant code
- likely cause
- suspect change
- a practical fix recommendation

This is the first point where the system can credibly suggest a full fix approach.

---

## Security, Storage, and Privacy

This feature indexes customer code, so the implementation must define boundaries clearly.

### Repository checkout storage

- repositories should be cloned into a controlled workspace-specific path
- checkouts should be isolated per repository
- temporary workdirs should be cleaned up after use when appropriate

### Data retention

- raw repository checkouts should not live forever unless there is a clear operational need
- indexed chunks and embeddings should have a defined retention policy
- disconnected repositories should support cleanup or archival workflows

### Model exposure

- only send the minimum necessary code context to reasoning models
- do not send whole repositories to an LLM
- prefer local parsing and structural extraction over model-based preprocessing

### Workspace isolation

- all code data, embeddings, commits, and analyses must remain scoped to a workspace
- cross-workspace retrieval must be impossible by construction

---

## Concurrency and Locking

### Repository indexing lock

- only one active indexing run per repository at a time
- repeated webhook events should coalesce when possible

### Idempotency

- indexing the same commit twice should be safe
- unchanged file hashes should avoid duplicate reprocessing and re-embedding

### Force-push and rebase handling

- incremental indexing should not assume linear history forever
- if `last_indexed_sha` is no longer reachable, the system should fall back to a safe recovery path

### Analysis behavior during indexing

- workspace analysis should use the latest successfully indexed state
- it should not block indefinitely waiting for a new index run to finish

---

## Recommended Model Strategy

### Indexing

- local `tree-sitter` parsing
- cheap embeddings or low-cost retrieval model
- avoid expensive frontier reasoning models during full-repo preprocessing

### Incident-time reasoning

- stronger model for diagnosis and fix suggestions
- use expensive reasoning only on a very small set of already-ranked snippets

This keeps indexing costs low while preserving analysis quality where it matters.

---

## Recommended Implementation Order

1. Add models + migrations (`code_repositories`, `code_chunks`, `code_commits`, `code_import_graph`, `incident_analyses`)
2. Add repository connection flow (GitHub integration)
3. Add initial indexing job (tree-sitter parse → chunks → embeddings)
4. Add import graph extraction during indexing (file-level import/require/include edges → `code_import_graph`)
5. Add structural summary generation during indexing (routes, schema, key modules → `code_repositories.structural_summary`)
6. Add incremental webhook indexing (push events → re-index changed files, update import graph + summary)
7. Add commit ingestion
8. Implement retrieval tools (`search_code`, `grep_exact`, `read_file`, `list_files`, `get_recent_commits`, `get_repo_info`, `get_structural_summary`, `get_blast_radius`)
9. Build analysis agent (LLM tool-use loop: orient with structural summary → explore → blast radius → synthesize)
10. Add `/ff analyze` command + incident analysis persistence + Slack delivery
11. Add `chunk_relationships` extraction + `get_chunk_relationships` tool (Phase 2)
12. Add exact snippet retrieval with surrounding context (Phase 2)
13. Add fix-plan generation (Phase 3)

---

## Rails Architecture Fit

This should follow the existing Firefight architecture style:

- webhook/controller -> job -> service -> persistence -> adapter

Suggested shape:

- `CodeIndexJob` -> `CodeIndexService`
- `AnalyzeIncidentCodeJob` -> `CodeAnalysisAgent` (tool-use loop with retrieval tools)
- Retrieval tools (`CodeSearchTool`, `CodeGrepTool`, `CodeReadFileTool`, etc.) query `code_chunks`, `code_commits`, `code_repositories` directly
- Slack command handler triggers analysis and posts via adapter

The analysis agent is a service object that runs an LLM tool-use loop. Each tool is a callable that queries the code index and returns structured results. The agent accumulates context across tool calls and produces a final `IncidentAnalysis`.

---

## Final Recommendation

Build this in three milestones:

1. Relevant code + suspect commits across workspace repositories
2. Exact snippets + higher precision across repositories
3. Suggested fix plan with microservice/shared-library awareness

This gives Firefight a credible path from code retrieval to actionable incident debugging without overcommitting to expensive or unreliable graph-heavy systems too early.
