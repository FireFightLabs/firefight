# Code Intelligence Ranking

## Goal

Define a simple, explicit ranking model for Phase 1 and Phase 2 of Code Intelligence.

This document exists so retrieval behavior is understandable, debuggable, and adjustable without relying on vague "best effort" ranking.

---

## Principles

- direct evidence beats inferred evidence
- stack-trace matches beat semantic similarity
- exact path matches beat fuzzy text similarity
- repository metadata and dependency hints are boosts, not hard truth
- stale or low-confidence data reduces score
- ranking should be explainable in the stored analysis output

---

## Ranking Inputs

Each candidate chunk may have some or all of these signals:

- direct stack-trace path match
- stack-trace line-range proximity
- exact file path mention in incident context
- semantic similarity score from vector search
- symbol/name match in incident text
- repository dependency-hint relationship
- repository classification/context match
- recent commit overlap
- chunk quality level
- repository freshness/index status

---

## Phase 1 Ranking Formula

Phase 1 should stay simple.

Suggested score:

```text
score =
  stack_trace_path_score +
  exact_path_match_score +
  semantic_similarity_score +
  dependency_hint_boost +
  repo_context_boost +
  recent_commit_boost -
  stale_index_penalty -
  low_confidence_chunk_penalty
```

### Suggested weights

These are starting values, not permanent truths.

#### Direct stack-trace path hit

- exact file hit: `+100`
- path suffix hit: `+60`

#### Stack-trace line proximity

- exact line inside chunk range: `+30`
- within +/- 10 lines: `+15`

#### Exact file path mention in incident context

- exact match: `+40`
- suffix/path fragment match: `+20`

#### Semantic similarity

Assuming normalized similarity in `0.0..1.0`:

- `semantic_similarity_score = similarity * 35`

#### Dependency hint boost

- repository explicitly depends on another candidate repo: `+10`
- shared library referenced by 2+ candidate service repos: `+20`

#### Repository classification/context boost

- incident mentions service matching repo `service_name`: `+15`
- repo kind matches context strongly (e.g. frontend incident + frontend repo): `+10`

#### Recent commit boost

- chunk file touched in last 24h: `+15`
- chunk file touched in last 48h: `+10`
- chunk file touched in last 7d: `+5`

#### Penalties

- repository stale: `-10`
- repository indexing failed or partial: `-20`
- fallback file-only chunk: `-15`
- low-confidence semantic extraction: `-10`

---

## Phase 2 Ranking Formula

Phase 2 adds more precision.

Suggested score:

```text
score =
  phase1_score +
  symbol_match_score +
  line_range_precision_score +
  structural_relationship_boost +
  snippet_density_boost
```

### Additional Phase 2 weights

#### Symbol/name match

- exact qualified symbol match: `+25`
- exact unqualified symbol match: `+15`
- fuzzy symbol/name match: `+8`

#### Line-range precision

- exact stack-trace line inside snippet: `+20`
- snippet adjacent to exact line: `+10`

#### Structural relationship boost

- parent container of top-ranked method/class: `+8`
- imported/inherited high-confidence related chunk: `+5`

#### Snippet density boost

Useful when many chunks come from the same file.

- small focused chunk with strong evidence: `+8`
- large coarse file chunk when smaller matching chunks exist: `-8`

---

## Repository Ranking

Repository score should be derived from the best chunk evidence plus coverage signals.

Suggested repository score:

```text
repository_score =
  best_chunk_score +
  second_best_chunk_bonus +
  commit_density_boost +
  dependency_support_boost -
  stale_index_penalty
```

### Suggested repository boosts

- second strong chunk in same repo: `+10`
- 3+ strong chunks in same repo: `+15`
- 2+ recent commits touching candidate files: `+10`
- repo supported by dependency hints from other top repos: `+10`

---

## Coverage Adjustment

Ranking and confidence must account for incomplete workspace coverage.

Suggested confidence modifiers:

- all likely repos indexed and fresh: `1.0x`
- one likely repo stale: `0.9x`
- one likely repo failed: `0.8x`
- multiple likely repos missing/stale: `0.6x`

This modifier should affect reported confidence, not necessarily hide results.

---

## Practical Scoring Examples

## Example 1: Strong stack-trace hit in one service repo

Incident context includes:

- `app/services/billing/retry_handler.rb:42`

Candidate chunk:

- exact file match: `+100`
- exact line inside chunk: `+30`
- semantic similarity `0.62`: `+21.7`
- recent commit in last 24h: `+15`

Total:

- `166.7`

This should outrank nearly everything else.

## Example 2: Shared library likely root cause

No exact stack trace to shared library, but:

- service repo chunk has high similarity: `+28`
- shared library chunk has strong similarity: `+25`
- library repo is dependency of two candidate services: `+20`
- recent commit touched shared library file in last 48h: `+10`

Total for shared library chunk:

- `55`

This may outrank weaker service-side fuzzy matches and surface the library as likely origin.

## Example 3: Stale repo penalty

Candidate chunk has:

- exact path mention: `+40`
- semantic similarity `0.50`: `+17.5`
- stale repository: `-10`

Total:

- `47.5`

Still relevant, but lower confidence than a fresh candidate.

## Example 4: Fallback file chunk vs semantic method chunk

Fallback file chunk:

- semantic similarity `0.70`: `+24.5`
- fallback penalty: `-15`
- total: `9.5`

Semantic method chunk:

- semantic similarity `0.58`: `+20.3`
- exact symbol match: `+15`
- total: `35.3`

The method chunk should win despite slightly lower raw similarity.

---

## Explanation Requirements

Analysis output should be able to explain why a chunk or repository ranked highly.

Examples:

- "Ranked highly due to exact stack-trace file match and recent commit overlap"
- "Boosted because this shared library is referenced by two candidate services"
- "Confidence reduced because the repository index is stale"

These explanations should come from the scoring signals, not be invented by the model.

---

## Implementation Guidance

- keep raw signal components alongside final score
- store per-signal contributions for debugging
- make weights configurable in code constants, not hardcoded across many files
- do not let the LLM decide ranking order

Suggested stored internal shape:

```json
{
  "score": 166.7,
  "signals": {
    "stack_trace_path": 100,
    "stack_trace_line": 30,
    "semantic_similarity": 21.7,
    "recent_commit": 15
  }
}
```

---

## Phase 1 Non-Goals

Do not do these in the initial ranking implementation:

- learned ranking models
- graph-centrality ranking
- full dependency graph inference
- deep language-specific call-resolution scoring

The first version should be simple, deterministic, and explainable.
