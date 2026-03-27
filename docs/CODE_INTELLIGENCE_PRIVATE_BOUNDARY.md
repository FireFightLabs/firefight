# Code Intelligence Private Boundary

## Goal

Define the architectural boundary between the public Firefight application and the private Code Intelligence system.

This document assumes:

- the main Firefight repository may be public
- the full Code Intelligence layer should remain private
- the parser is not the only proprietary component
- the actual moat includes retrieval, ranking, reasoning, and fix guidance

---

## Decision

The full Code Intelligence layer should live in a separate private repository.

That private repository should contain:

- a private Rails engine or Rails application for Code Intelligence
- the private Go CLI parser/indexer

The public Firefight repository should contain only:

- product integration hooks
- controller/job/command entry points that trigger analysis
- models or adapters for storing/displaying returned analysis results
- a client boundary for talking to the private Code Intelligence system

---

## Why This Boundary Exists

If the public Firefight repo contains the retrieval, ranking, and reasoning code, then the actual intelligence layer is public even if the parser remains private.

That is not enough if the moat is the full system.

The real defensible value is not just:

- tree-sitter parsing
- chunk extraction
- embeddings

The real defensible value is the system that:

- searches across many repositories in one workspace
- ranks the right code paths during incidents
- correlates code with recent changes
- assembles the right snippets and context
- reasons about likely root cause
- suggests the right fix path

That entire intelligence layer should remain private if it is considered core IP.

---

## What Stays Private

The private Code Intelligence repository should own:

### Parsing and indexing

- Go CLI parser
- tree-sitter integration
- chunk extraction rules
- hashing logic
- language-specific heuristics

### Retrieval and ranking

- workspace-wide multi-repo search
- direct path lookup
- vector retrieval
- ranking formulas
- repository/dependency-hint scoring
- coverage/confidence logic

### Analysis and reasoning

- incident-context assembly
- commit correlation
- prompt construction
- reasoning orchestration
- structured analysis generation
- suggested fix generation

### Operational logic

- indexing lifecycle
- retry logic for indexing workflows
- cost controls and quotas
- freshness/staleness handling
- partial coverage handling

---

## What Stays Public In Firefight

The public Firefight app should continue to own:

### Product workflows

- incidents
- Slack flows
- commands and interactions
- UI surfaces
- API surfaces

### Integration boundary

- command handlers that trigger analysis
- jobs that call the private engine
- adapters/clients for the private engine
- persistence of returned analysis summaries if needed by the product

### Presentation

- posting analysis into incident channels
- rendering analysis in the web UI
- exposing analysis in timeline/history

Firefight remains the product shell.
The private intelligence engine becomes the proprietary analysis backend.

---

## Recommended Architecture

## Public repository

This repository should contain:

- `AnalyzeIncidentCodeJob` trigger point or equivalent
- `CodeIntelligenceClient` or equivalent boundary object
- models used to store or reference analysis results in Firefight
- Slack/UI/API integration code

It should not contain:

- ranking implementation
- retrieval formulas
- prompt construction internals
- parser/chunker logic
- workspace-wide intelligence heuristics

## Private repository

The private repository should contain:

- private Rails engine or Rails application
- private Go CLI parser
- indexing/retrieval/ranking/reasoning logic
- persistence and operational code specific to intelligence

---

## Private Repo Structure

Recommended shape:

```text
code-intelligence-private/
  app/
    models/
    services/
    jobs/
    clients/
  lib/
    code_intelligence/
  config/
  db/
  tools/
    code-indexer/   # Go CLI source
```

Two viable forms:

### Option A: Private Rails application

- runs as its own internal service
- Firefight calls it over HTTP/gRPC/internal API

### Option B: Private Rails engine

- mounted or loaded into Firefight deploys as a private dependency
- Firefight calls it in-process

---

## Recommended Form

The recommended form is:

- separate private repository
- private Rails application/service
- Go CLI bundled inside that private repo

Why this is preferable:

- stronger private/public boundary
- easier to keep the intelligence layer fully proprietary
- cleaner ownership of indexing, retrieval, and reasoning
- easier to evolve independently from the public Firefight app

---

## Why Not Only A Private Go CLI

Keeping only the parser private is not enough if the intelligence engine is the moat.

If Firefight public code still contains:

- retrieval logic
- ranking logic
- reasoning orchestration
- confidence handling
- analysis heuristics

then the most valuable parts are still public.

The parser alone is not the whole differentiator.

---

## Interface Between Public App And Private Engine

The public app should talk to the private engine through a narrow client boundary.

### Suggested responsibilities of `CodeIntelligenceClient`

- request repository indexing
- request incident analysis
- fetch analysis results/status
- pass workspace and repository identifiers
- handle retries and error translation

### Suggested operations

- `index_repository(workspace_id:, repository_id:)`
- `analyze_incident(workspace_id:, incident_id:, context:)`
- `get_analysis(analysis_id:)`

The public app should send context and receive results, not own the internal analysis workflow.

---

## Data Ownership Options

There are two valid patterns.

### Option 1: Private engine owns all intelligence data

Private system stores:

- repositories
- chunks
- embeddings
- commits
- analyses

Public Firefight app stores only references and user-facing summaries.

Pros:

- strongest IP protection
- clean separation

Cons:

- more integration work

### Option 2: Firefight stores returned analysis summaries only

Private system stores internal working data.
Public app stores only the final analysis record needed for UI/history.

This is usually the best choice.

---

## Recommended Boundary Of Responsibility

### Public Firefight app

- incident lifecycle
- Slack/UI/API workflows
- invoking private intelligence operations
- rendering/storing user-facing analysis summaries

### Private Code Intelligence engine

- parsing
- indexing
- retrieval
- ranking
- reasoning
- fix suggestion generation
- intelligence-side persistence

---

## Deployment Implications

If the intelligence engine is private and separate:

- Firefight deploys independently
- Code Intelligence deploys independently
- the Go CLI is deployed with the private intelligence service
- Firefight does not need access to private parser source code

This is the cleanest setup if the public repo is open source.

---

## Security Considerations

- workspace isolation must exist in both systems
- only minimum incident context should cross the boundary
- only minimum analysis output should be returned to Firefight
- repository contents should stay inside the private intelligence system

---

## Future Evolution

This boundary also makes it easier later to:

- scale indexing separately from Firefight core
- support other products on top of the same intelligence engine
- add logs/metrics/deploy intelligence privately
- expand from code diagnosis into patch generation and draft PR creation

---

## Final Recommendation

If the full Code Intelligence layer is part of the moat, then:

- do not keep retrieval/ranking/reasoning code in the public Firefight repo
- create a separate private repository
- put the private Rails intelligence engine and private Go parser there
- keep the public Firefight app as the product shell and integration layer

That gives the cleanest boundary between the public application and the proprietary intelligence system.
