# Code Intelligence Phase 1 Rails Plan

## Goal

Define the Rails-side implementation for Phase 1 of Code Intelligence:

- multi-repo workspace support
- repository indexing orchestration
- chunk and commit storage
- retrieval across repositories
- manual incident analysis via `/ff analyze`

This document intentionally focuses on the Rails application side. The Go parser CLI is treated as a deterministic external worker tool.

---

## Rails Responsibilities In Phase 1

Rails owns:

- repository connection and workspace association
- clone/fetch lifecycle
- indexing orchestration
- persistence of repositories, chunks, commits, and analyses
- embeddings
- workspace-wide retrieval and ranking
- analysis execution
- Slack/API/UI delivery
- quotas, locking, and observability

---

## Data Model

## 1. `code_repositories`

Tracks connected repositories per workspace.

Suggested columns:

```ruby
# References
#   workspace_id        :bigint, not null
#
# Provider/repo identity
#   provider            :string, not null     # github, gitlab later
#   owner               :string, not null
#   name                :string, not null
#   external_id         :string               # provider repo id if available
#   default_branch      :string, not null
#
# Indexing lifecycle
#   status              :string, not null     # pending, indexing, indexed, failed, paused
#   last_indexed_sha    :string
#   indexed_at          :datetime
#   last_error          :text
#
# Multi-repo metadata
#   repo_kind           :string               # service, library, frontend, infra
#   service_name        :string
#   owned_by_team       :string
#   dependency_hints    :jsonb, default: {}
#
# Cost / observability
#   files_indexed_count :integer, default: 0, null: false
#   chunks_indexed_count :integer, default: 0, null: false
#   last_index_duration_ms :integer
#
# Timestamps
#   created_at          :datetime
#   updated_at          :datetime
```

Recommended indexes:

- unique `(workspace_id, provider, owner, name)`
- `(workspace_id, status)`
- `(workspace_id, repo_kind)`

Recommended model methods/scopes:

- `active`
- `ready_for_analysis`
- `stale?`
- `indexing?`

## 2. `code_chunks`

Searchable code units extracted from the CLI.

Suggested columns:

```ruby
# References
#   code_repository_id  :bigint, not null
#
# Identity
#   file_path           :string, not null
#   language            :string, not null
#   chunk_type          :string, not null     # file, class, module, method, function
#   name                :string
#   qualified_name      :string
#   parent_qualified_name :string
#
# Content
#   content             :text, not null
#   file_hash           :string, not null
#   content_hash        :string, not null
#
# Source range
#   start_line          :integer, not null
#   end_line            :integer, not null
#
# Index versioning
#   commit_sha          :string, not null
#   indexed_at          :datetime, not null
#   deleted_at          :datetime
#
# Retrieval
#   embedding           :vector
#
# Timestamps
#   created_at          :datetime
#   updated_at          :datetime
```

Recommended indexes:

- `(code_repository_id, file_path)`
- unique `(code_repository_id, file_path, content_hash, start_line, end_line)` where practical
- `(code_repository_id, qualified_name)`
- `(code_repository_id, commit_sha)`
- HNSW/IVFFlat index on `embedding`

Recommended scopes:

- `active`
- `for_file(path)`
- `for_repository(repo)`

## 3. `code_commits`

Commit metadata used for change correlation.

Suggested columns:

```ruby
# References
#   code_repository_id  :bigint, not null
#
# Identity
#   sha                :string, not null
#   message            :text, not null
#   author             :string, not null
#   committed_at       :datetime, not null
#
# Change payload
#   files_changed      :jsonb, not null      # array of file paths
#   diff_summary       :text
#
# Timestamps
#   created_at         :datetime
#   updated_at         :datetime
```

Recommended indexes:

- unique `(code_repository_id, sha)`
- `(code_repository_id, committed_at)`

## 4. `incident_analyses`

Stores the analysis output presented to responders.

Suggested columns:

```ruby
# References
#   incident_id         :bigint, not null
#
# Query / coverage
#   query_context       :text, not null
#   coverage_summary    :jsonb, default: {}
#
# Results
#   suspect_repositories :jsonb, default: []
#   relevant_chunks     :jsonb, default: []
#   suspect_commits     :jsonb, default: []
#   confidence_score    :decimal(5,2)
#   explanation         :text
#   suggested_fix       :text
#   recommended_next_checks :jsonb, default: []
#
# Metadata
#   model_used          :string, not null
#   analyzed_at         :datetime, not null
#
# Timestamps
#   created_at          :datetime
#   updated_at          :datetime
```

Recommended indexes:

- `(incident_id, analyzed_at)`

---

## Suggested Associations

```ruby
class CodeRepository < ApplicationRecord
  belongs_to :workspace
  has_many :code_chunks, dependent: :destroy
  has_many :code_commits, dependent: :destroy
end

class CodeChunk < ApplicationRecord
  belongs_to :code_repository
end

class CodeCommit < ApplicationRecord
  belongs_to :code_repository
end

class IncidentAnalysis < ApplicationRecord
  belongs_to :incident
end
```

---

## Jobs And Services

## `CodeIndexJob`

Purpose:

- run one repository indexing pass

Inputs:

- `code_repository_id`
- optional `changed_files`
- optional `target_sha`

Responsibilities:

- acquire repository-level lock
- ensure checkout exists and is current
- decide full vs incremental indexing
- invoke `CodeIndexerCli`
- pass result to `CodeIndexService`
- update repository status / timestamps / counters

## `CodeIndexService`

Purpose:

- ingest one CLI result and reconcile repository state

Responsibilities:

- parse file statuses
- delete chunks for removed files
- mark previous chunks stale when file contents changed
- upsert new chunks
- determine which chunks need embeddings
- record indexing statistics

## `CodeIndexerCli`

Purpose:

- thin wrapper around the Go CLI

Responsibilities:

- build command
- write temp `files.json` if needed
- run CLI
- capture stdout/stderr/exit code
- parse JSON output
- return structured Ruby object or hash

## `CodeEmbeddingJob`

Purpose:

- embed changed/new chunks only

Responsibilities:

- batch embeddings
- obey workspace quotas
- update `embedding` on `CodeChunk`

## `CodeSearchService`

Purpose:

- retrieve candidate code across all indexed repositories in a workspace

Responsibilities:

- extract stack-trace paths if present
- do direct file-path lookup
- do vector search
- merge and dedupe results
- apply ranking boosts from repo metadata and dependency hints
- return ranked candidate chunks and repositories

## `CodeAnalysisService`

Purpose:

- turn incident context + retrieved code + recent commits into an analysis

Responsibilities:

- assemble prompt context
- include coverage summary
- call model
- persist `IncidentAnalysis`
- return output for Slack/UI delivery

## `AnalyzeIncidentCodeJob`

Purpose:

- background analysis for a specific incident

Responsibilities:

- load incident and workspace
- call `CodeSearchService`
- call `CodeAnalysisService`
- post result via adapter

---

## Ranking Strategy For Phase 1

Implement ranking in Rails, not in the CLI.

Recommended priority order:

1. direct stack-trace path hits
2. exact file path matches found in incident text
3. semantic similarity score
4. repository dependency-hint boost
5. repository classification/context boost
6. recent commit boost

Practical rules:

- stack-trace hits always outrank pure semantic results
- shared library repos get boosted when multiple candidate service repos reference them
- fallback file-level chunks rank below good semantic chunks
- stale repository indexes reduce confidence

---

## Partial Coverage Behavior

Analysis must proceed with incomplete coverage.

Examples:

- some repositories are not connected
- some repositories failed indexing
- some repositories are stale

Required behavior:

- analysis still runs
- result includes coverage summary
- confidence is reduced when relevant repos are stale or unavailable

Suggested `coverage_summary` shape:

```json
{
  "repositories_connected": 6,
  "repositories_indexed": 4,
  "repositories_stale": 1,
  "repositories_failed": 1
}
```

---

## Repository Metadata And Dependency Hints

Use simple metadata first.

Examples:

- `repo_kind = service`
- `repo_kind = library`
- `service_name = billing-api`
- `owned_by_team = payments`

Suggested `dependency_hints` examples:

```json
{
  "depends_on": ["shared-auth", "event-schema"],
  "used_by": ["checkout-api"],
  "consumes_events_from": ["billing-api"]
}
```

These should be ranking signals only, not hard constraints.

---

## Locking And Concurrency

## Repository-level locking

- only one active indexing run per repository
- duplicate pushes should coalesce where possible

## Safe reindex behavior

- if `last_indexed_sha` is invalid after force-push/rebase, do a safe fallback reindex for that repository

## Analysis behavior during indexing

- analysis uses latest successful index state
- analysis must not wait indefinitely for active indexing runs

---

## Security And Storage

### Repository checkouts

- Rails manages clone paths
- per-repository checkout isolation
- retention / cleanup policy must be explicit

### Data minimization

- only selected snippets/chunks go to models
- whole repositories should never be sent to LLMs

### Workspace isolation

- all repository/chunk/commit/analysis records are scoped to a workspace

---

## Suggested Migration Order

1. `code_repositories`
2. `code_chunks`
3. enable `pgvector`
4. add `embedding` to `code_chunks`
5. `code_commits`
6. `incident_analyses`

---

## Suggested Phase 1 Delivery Order

1. models + migrations
2. `CodeIndexerCli` wrapper
3. `CodeIndexJob` + `CodeIndexService`
4. repository connect + initial index flow
5. push webhook incremental indexing
6. `CodeEmbeddingJob`
7. `CodeSearchService`
8. `/ff analyze`
9. `AnalyzeIncidentCodeJob`
10. `CodeAnalysisService`

---

## Final Recommendation

Keep the Rails side responsible for workspace-level intelligence and multi-repo reasoning.

The Go CLI should stay narrow and deterministic.

That keeps the expensive product decisions in one place while still getting the performance benefits of a compiled parser.
