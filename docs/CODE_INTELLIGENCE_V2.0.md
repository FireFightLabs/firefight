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
    -> CodeSearchService
      -> direct file/path lookup from stack trace
      -> vector search over chunks across all workspace repositories
      -> rank + merge results
    -> CodeAnalysisService
      -> add recent suspect commits
      -> add code snippets / line ranges
      -> ask model for diagnosis
    -> persist IncidentAnalysis
    -> post result to incident channel
```

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

- `code_repositories`
- `code_chunks`
- `code_commits`
- `incident_analyses`

`chunk_relationships` is optional in Phase 1 and should be limited to only very high-confidence relationships if included at all.

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

#### 7. Retrieval pipeline

`CodeSearchService` should use two paths across all repositories connected to the workspace:

- direct file/path lookup from stack traces
- vector search over indexed chunks

Then:

- merge
- dedupe
- rank
- group results by repository when presenting them

### Ranking Strategy For Phase 1

Phase 1 should use a simple explicit ranking model.

Recommended weighting order:

1. direct stack-trace file/path hit
2. exact file path match from incident context
3. high semantic similarity from vector search
4. repository dependency hint boost
5. repository classification boost when it matches incident context
6. commit recency boost for touched files

Practical rules:

- stack trace hits outrank everything else
- shared libraries should be boosted when multiple candidate service repos point toward the same library repo
- low-confidence fallback file chunks should rank below well-formed semantic chunks
- repositories with stale or partial indexes should be penalized slightly, not excluded automatically

#### 8. Analysis pipeline

`CodeAnalysisService` should assemble:

- incident context
- top candidate chunks
- top candidate repositories
- relevant file paths + line ranges
- recent commits touching those files

And return:

- likely root cause
- likely affected repository or repositories
- relevant code areas
- suspect commit(s)
- recommended next checks

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

1. Add models + migrations
2. Add repository connection flow
3. Add initial indexing job
4. Add incremental webhook indexing
5. Add commit ingestion
6. Add vector search service
7. Add `/ff analyze`
8. Add incident analysis persistence + Slack delivery
9. Add exact snippet retrieval
10. Add fix-plan generation

---

## Rails Architecture Fit

This should follow the existing Firefight architecture style:

- webhook/controller -> job -> service -> persistence -> adapter

Suggested shape:

- `CodeIndexJob` -> `CodeIndexService`
- `AnalyzeIncidentCodeJob` -> `CodeSearchService` -> `CodeAnalysisService`
- Slack command handler triggers analysis and posts via adapter

---

## Final Recommendation

Build this in three milestones:

1. Relevant code + suspect commits across workspace repositories
2. Exact snippets + higher precision across repositories
3. Suggested fix plan with microservice/shared-library awareness

This gives Firefight a credible path from code retrieval to actionable incident debugging without overcommitting to expensive or unreliable graph-heavy systems too early.
