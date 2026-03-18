# Code Intelligence

## Context

When an incident occurs, responders need to quickly understand what broke and why. Today this is manual — engineers read logs, search code, check recent deploys, and correlate changes by hand.

Code Intelligence gives Firefight the ability to index a workspace's codebase, understand its structure, and — when an incident fires — automatically identify the relevant code paths, suspect commits, and likely root cause. This is the first building block; it will later combine with logs and metrics for full automated diagnosis.

---

## Architecture

### Data Flow

```
GitHub repo (webhook: push)
  → CodeIndexJob (background, incremental)
    → Tree-sitter parse → semantic chunks (functions, classes, modules)
    → RubyLLM.embed → vector embeddings
    → Extract relationships (calls, contains, imports, inherits)
    → Store in PostgreSQL (pgvector)

Incident created / analysis requested
  → CodeAnalysisService
    → Build query from incident context (error message, stack trace, affected service)
    → Vector search → top-K seed chunks
    → Graph expansion → 1-2 hops via chunk_relationships
    → Git correlation → recent commits touching expanded chunks
    → LLM analysis → diagnosis + suspect commit + suggested fix
    → Store result as IncidentAnalysis
    → Post to incident channel
```

### Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| LLM client | RubyLLM | Ruby-native, supports embeddings + chat + tool use, Rails integration, provider-agnostic |
| Embeddings | pgvector (PostgreSQL extension) | Already on Postgres, native vector similarity search, no separate infra |
| Code parsing | Tree-sitter (via `tree_sitter` gem) | AST-aware semantic chunking, supports all major languages |
| Relationships | PostgreSQL tables + recursive CTEs | 1-2 hop traversals are trivial for Postgres, no graph DB needed |
| Git integration | GitHub API (via `octokit` or webhooks) | Push webhooks for incremental indexing, API for commit/diff data |

---

## Data Model

### code_repositories

Tracks connected repositories per workspace.

```ruby
# Columns:
#   workspace_id   :bigint, not null
#   provider       :string, not null  (e.g. "github")
#   owner          :string, not null  (e.g. "firefightlabs")
#   name           :string, not null  (e.g. "api-server")
#   default_branch :string, not null  (e.g. "main")
#   last_indexed_sha :string          (last fully indexed commit)
#   indexed_at     :datetime
```

### code_chunks

Semantic units of code extracted by tree-sitter.

```ruby
# Columns:
#   code_repository_id :bigint, not null
#   file_path          :string, not null    (e.g. "app/services/billing.rb")
#   chunk_type         :string, not null    (function, class, module, method, block)
#   name               :string             (e.g. "charge!", "BillingService")
#   content            :text, not null      (raw source code of the chunk)
#   embedding          :vector, not null    (pgvector)
#   start_line         :integer, not null
#   end_line           :integer, not null
#   language           :string, not null    (ruby, javascript, python, etc.)
#   commit_sha         :string, not null    (SHA when this chunk was indexed)
#   indexed_at         :datetime, not null
#
# Indexes:
#   (code_repository_id, file_path)         — for incremental re-indexing (delete old chunks per file)
#   embedding using hnsw (vector_cosine_ops) — for similarity search
```

### chunk_relationships

Edges between chunks representing code structure and dependencies.

```ruby
# Columns:
#   source_chunk_id    :bigint, not null
#   target_chunk_id    :bigint, not null
#   relationship_type  :string, not null
#
# Relationship types:
#   contains  — class/module contains a method/function (tree-sitter parent-child)
#   calls     — chunk A references a symbol defined in chunk B
#   imports   — file A requires/imports file B
#   inherits  — class A inherits from or includes class B
#
# Index:
#   (source_chunk_id, relationship_type)
#   (target_chunk_id, relationship_type)
```

### code_commits

Recent commit history for git correlation.

```ruby
# Columns:
#   code_repository_id :bigint, not null
#   sha                :string, not null
#   message            :text, not null
#   author             :string, not null
#   committed_at       :datetime, not null
#   files_changed      :jsonb, not null    (array of file paths)
#   diff_summary       :text               (condensed diff for LLM context)
```

### incident_analyses

Stored analysis results tied to incidents.

```ruby
# Columns:
#   incident_id        :bigint, not null
#   code_repository_id :bigint             (null if analysis spans multiple repos)
#   query_context      :text, not null     (the input: error message, stack trace, etc.)
#   relevant_chunks    :jsonb              (array of chunk IDs with relevance scores)
#   suspect_commits    :jsonb              (array of {sha, file_path, reason})
#   explanation        :text               (LLM-generated diagnosis)
#   suggested_fix      :text               (LLM-generated fix suggestion)
#   model_used         :string, not null
#   analyzed_at        :datetime, not null
```

---

## Indexing Pipeline

### Initial Index

On repository connection, index the full codebase:

1. Clone/fetch the repo (shallow clone, HEAD only)
2. Walk all source files (filter by language extensions, skip vendored/generated code)
3. For each file:
   - Parse with tree-sitter → extract semantic nodes (functions, classes, methods, modules)
   - Chunk each node (target 500-1500 tokens, large nodes split with overlap)
   - Generate embeddings via `RubyLLM.embed` (batch requests)
   - Extract relationships from AST (contains, imports, inherits)
4. Basic symbol-reference analysis for `calls` edges (function name appears in another chunk's body)
5. Store chunks, relationships, and commit history

### Incremental Re-index

On push webhook, only process what changed:

```
push event → changed_files (from webhook payload or git diff last_indexed_sha..HEAD)

For each changed file:
  1. Delete existing code_chunks for that file (cascade deletes relationships)
  2. Re-parse, re-chunk, re-embed
  3. Rebuild relationships for new chunks

For deleted files:
  1. Delete chunks + relationships

Update last_indexed_sha on code_repository
```

Cost is proportional to the diff, not the repo size. A typical push touches 1-10 files.

### Relationship Extraction

From tree-sitter AST (high confidence):
- **contains**: direct parent-child in the AST (class → method)
- **imports**: `require`, `import`, `include` statements → resolve to file paths
- **inherits**: `class A < B`, `include ModuleName` → resolve to chunk by name

From symbol matching (lower confidence, still useful):
- **calls**: function/method name appears as a call expression in another chunk. Tree-sitter identifies call expressions, so this is better than naive string matching.

---

## Retrieval Pipeline

When an incident needs analysis:

### Step 1 — Build Query

Extract signal from incident context:
- Error message / exception class
- Stack trace (file paths + line numbers)
- Affected service name
- Any description provided by the responder

Stack traces are gold — file paths go directly to the graph, skipping vector search.

### Step 2 — Seed Retrieval

Two parallel paths:
- **Direct lookup**: if stack trace has file paths, fetch chunks for those files directly
- **Vector search**: embed the query, find top-K similar chunks (K=10-20)

Merge and deduplicate.

### Step 3 — Graph Expansion

From seed chunks, traverse 1-2 hops via `chunk_relationships`:

```sql
WITH RECURSIVE related AS (
  SELECT target_chunk_id AS chunk_id, relationship_type, 1 AS depth
  FROM chunk_relationships
  WHERE source_chunk_id = ANY(seed_chunk_ids)

  UNION

  SELECT cr.target_chunk_id, cr.relationship_type, r.depth + 1
  FROM chunk_relationships cr
  JOIN related r ON cr.source_chunk_id = r.chunk_id
  WHERE r.depth < 2
)
SELECT DISTINCT cc.*
FROM code_chunks cc
JOIN related r ON cc.id = r.chunk_id;
```

Also traverse inbound edges (who calls this chunk?) for root cause tracing.

### Step 4 — Git Correlation

Find recent commits touching any file in the expanded chunk set:

```ruby
CodeCommit
  .where(code_repository_id: repo.id)
  .where("committed_at > ?", incident.created_at - 48.hours)
  .where("files_changed ?| array[:paths]", paths: expanded_file_paths)
  .order(committed_at: :desc)
```

### Step 5 — LLM Analysis

Assemble context and prompt the LLM:

```
System: You are a senior engineer diagnosing a production incident.

Context:
- Incident: {title, description, severity, error messages}
- Relevant code: {expanded chunks with file paths and line numbers}
- Recent changes: {suspect commits with diffs}
- Deploy history: {last deploy SHA and timestamp}

Tasks:
1. Identify the most likely root cause
2. Explain why this caused the incident
3. Identify the specific commit that introduced the issue (if applicable)
4. Suggest a fix
```

---

## Implementation Phases

### Phase 1 — Foundation

Data model, repository connection, and basic indexing.

- [ ] Add `rubyllm` and `tree_sitter` gems
- [ ] Enable pgvector extension
- [ ] Create migrations: `code_repositories`, `code_chunks`, `chunk_relationships`, `code_commits`
- [ ] `CodeRepository` model with workspace association
- [ ] Tree-sitter parsing service: file → semantic chunks
- [ ] Embedding service: chunks → vectors via RubyLLM
- [ ] Relationship extraction from AST (contains, imports, inherits)
- [ ] `CodeIndexService` orchestrating parse → embed → store
- [ ] `CodeIndexJob` for background processing
- [ ] Initial full-index Rake task for testing

### Phase 2 — Incremental Indexing

Keep the index fresh without re-processing everything.

- [ ] GitHub webhook endpoint for push events
- [ ] Incremental indexing: diff-based file detection, delete-and-replace per file
- [ ] Commit history ingestion (store recent commits with file lists and diff summaries)
- [ ] Symbol-reference analysis for `calls` relationship edges

### Phase 3 — Retrieval and Analysis

The query pipeline that turns incident context into a diagnosis.

- [ ] `CodeSearchService`: vector search + direct file lookup
- [ ] Graph expansion: recursive CTE traversal from seed chunks
- [ ] Git correlation: match expanded chunks against recent commits
- [ ] `CodeAnalysisService`: assemble context, call LLM, return structured result
- [ ] `IncidentAnalysis` model to store results
- [ ] `AnalyzeIncidentCodeJob` triggered on incident creation or on demand

### Phase 4 — Integration

Surface results in the incident workflow.

- [ ] Post analysis to incident Slack channel (adapter method)
- [ ] `/ff analyze` slash command to trigger on-demand analysis
- [ ] Analysis visible in incident timeline (as an `IncidentEvent`)
- [ ] Support multi-repo workspaces (search across all connected repos)

---

## Open Questions

- **Embedding model choice**: `text-embedding-3-small` (OpenAI) vs open-source sentence-transformers vs Anthropic embeddings (when available). Trade-off is cost/speed vs quality. Start with OpenAI, swap later via RubyLLM's provider abstraction.
- **Chunk size tuning**: 500-1500 tokens is the target range. Needs experimentation — too small loses context, too large dilutes the embedding. May need language-specific defaults.
- **Rate limits**: Embedding thousands of chunks on initial index will hit API rate limits. Batch with backoff, or use a local model for initial bulk indexing.
- **Private repos / auth**: GitHub App installation for repo access. Tokens scoped per workspace.
- **Multi-language support**: Tree-sitter supports ~50 languages. Start with Ruby/JS/Python/Go, expand based on demand.
- **Cost**: Embedding storage in pgvector is cheap. LLM calls per analysis are the main cost. Consider caching analysis results and only re-running when new context arrives.
