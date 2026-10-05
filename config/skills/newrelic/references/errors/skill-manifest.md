# skill-manifest — apm-error-investigation

- **manifest_version**: `"1.0"`

## Identity

- **skill**
  - **name**: `newrelic/apm-error-investigation`
  - **version**: `1.0.0`
  - **description**: Root-causes a backend APM application error end to end — resolves the entity, ranks error groups by impact, follows the chosen trace, and correlates logs into an evidence-backed report.
- **author**
  - **verified_identity**: `New Relic`

## Provenance and testing

- **Skill version**: `1.0.0`
- **License**: Apache 2.0 (`LICENSE`, in this directory)
- **Last tested**: 2026-08-26
- **Models used**
  - Live query and tool verification: Claude Opus 5 (1M context), model id `claude-opus-5[1m]`.
  - Routing, coexistence and adversarial scoring: `claude-sonnet-4-6` and `claude-haiku-4-5`.
- **Results**: routing 31/31 (Sonnet) and 30/31 (Haiku) across 32 cases, no false-positive
  triggering between the three skills in this repository, and no failures across 7 distinct
  adversarial samples. Full detail, method and limitations in `evals/eval_results.md`; cases in
  `evals/test_cases.json`.
- **Not yet scored**: end-to-end workflow execution — the trigger cases' `must` clauses describe
  full runs and were not exercised. Non-Anthropic model families are unverified.
- **Tool dependency**: step 4 needs `get_distributed_trace_details`. Confirm it is generally
  available on the production MCP server — see the availability note under Privilege & actions.

Model behaviour drifts between versions, so these results are valid for the models and date above
only. Re-run `evals/` when the upstream model version changes, or when a New Relic agent or MCP tool
release could move the attribute-coverage figures this skill relies on.

## Security disclosures

### Input trust & prompt injection

- **processes_untrusted_input**: `true`
- **untrusted_input_sources**:
  - Error records from `TransactionError` — `error.message`, `error.class`, `transactionName`, `request.uri`, `host`. Exception messages are written by the monitored application and frequently embed request-supplied data, so their content is influenceable by anyone who can reach the application.
  - Log lines from `Log` — `message` and `level`. A log body is arbitrary attacker-reachable text.
  - Span and entity metadata from `Span` — span `name`, `entity.name`, `category`.
  - Entity names and account names returned by the lookup tools.

**Highest-exposure note.** This skill does not merely summarize untrusted text — it *makes control
decisions from it*. Error messages drive which error group is ranked first, and the chosen group
determines which trace is investigated. A crafted `error.message` or log line can therefore attempt
to steer the investigation itself, not just the wording of the report.

**Mitigation.** `SKILL.md` instructs the model to treat all retrieved telemetry as data rather than
instructions, to quote and flag any value that reads like a directive, and never to let retrieved
text change which tools are called, widen a time window, or alter what is disclosed. Per the EPD
Non-Boundary Rule this is a mitigation and **not** a security boundary — the boundary is the
read-only OAuth scope below plus the customer's own runtime sandbox.

### Data handling

- **handles_sensitive_data**: `true`
- **data_categories**:
  - `pii`
  - `credentials`
  - `confidential`
- **data_egress**: New Relic MCP server (NerdGraph) over HTTPS — the only destination the skill sends to, and it reaches it only through the MCP client's existing authenticated connection. Every error record, span and log line the skill reads additionally enters the agent's model context, so the customer's configured LLM inference provider receives it.
- **third_party_subprocessors**:
  - The customer's configured LLM inference provider — receives error messages and stack context, log message bodies, span and entity names, hostnames, request URIs, and trace IDs.
- **data_retention**: None by the skill. It writes no files and explicitly instructs against caching the resolved entity or GUID between runs. The account-name-to-ID mapping may be reused within a single session, in context only. The New Relic MCP server separately records one tool-invocation event per call — see `data_logging`.
- **data_logging**: None written by the skill. The New Relic MCP server records a tool-invocation event per call containing the invoking user's email and ID, the organization ID, and each tool parameter as `param_<name>` truncated to 100 characters. Parameter keys named exactly `password`, `token`, `key` or `secret` are omitted; `nrql_query` is not, so submitted NRQL text — including literal values in `WHERE` clauses — is recorded. The skill itself reads and logs no credential.

**Credential-exposure note — read this one.** Raw `Log.message` values in real applications can be
multi-kilobyte HTTP header dumps that include `authorization: Bearer …`. Any such value the skill
reads enters the agent transcript and the model provider's request payload. The skill mitigates
this by always truncating log messages with `substring(message, 0, 500)`, but customers should
understand the limit of that control: **truncation bounds context size, it does not reliably remove
credentials.** A bearer token appearing early in a header dump still falls inside the first 500
characters. Customers who forward raw request headers into logs should expect secrets in log bodies
to be reachable by any agent with `observability:read`, and should scrub at the log-forwarding layer
rather than relying on this skill.

**PII note.** Error and log bodies routinely carry user identifiers, email addresses, request paths
containing account or order IDs, and hostnames. The skill does not target these but cannot avoid
them, since they are embedded in the evidence it exists to read.

### Privilege & actions

- **oauth_scopes**:
  - `observability:read`
- **mcp_tools**:
  - `get_entity` — read-only; resolves the target to one APM `APPLICATION` entity.
  - `convert_time_period_to_epoch_ms` — read-only; converts a described time window to epoch bounds.
  - `execute_nrql_query` — read-only; the primary data path. Ranks error groups by impact (step 3a), fetches candidate traces for the chosen error (step 3b), and runs the sampling check that decides which candidates are inspectable (step 3c). Query templates ship in `queries.md`.
  - `get_distributed_trace_details` — read-only; resolve a whole distributed trace across accounts, returning per-service self-time, the call graph and error spans.
  - `analyze_entity_logs` — read-only; correlates logs around the error.

  Every tool is read-only. `AskUserQuestion` is used to put entity and error-group choices to the
  user. The skill explicitly does **not** call `generate_alert_insights_report`, and does not use
  `search_traces`.

  **Availability — audited 2026-08-26.** Four of the tools above were generally available to a
  customer: `get_entity`, `convert_time_period_to_epoch_ms`, `execute_nrql_query` and
  `analyze_entity_logs`. The step-4 trace tool — `get_distributed_trace_details` — was **not yet
  generally available** on the production MCP server at the time of the audit. Confirm that it is
  before relying on step 4.

  Steps 3a–3c deliberately use `execute_nrql_query` rather than the typed error tools, so the
  error-ranking path carries no availability dependency at all. Step 4 is the only affected step,
  and it does not degrade: the skill's central finding is that a single-account NRQL query cannot
  resolve a distributed trace and that no rewrite fixes it. **Confirm the trace tool is generally
  available on the production MCP server before publishing** — that is the one outstanding item.
  See `evals/eval_results.md`.

  **Privilege note on the NRQL path.** `execute_nrql_query` takes a query string rather than typed
  parameters, so it is broader than the typed tools it replaces: within `observability:read` it can
  read any event type in the account, not only error data. This does not widen the OAuth scope —
  the same scope already permits it — but it does widen what the skill could read if its
  instructions were subverted. `SKILL.md` constrains the queries to the templates in `queries.md`;
  per the Non-Boundary Rule that is a mitigation, not a boundary.
- **network_access**: `true`
- **network_endpoints**:
  - **host**: `<the New Relic MCP server host configured in the customer's MCP client>`
    **port**: `443`
    **justification**: Sole transport for all tool calls. The skill issues no raw HTTP of its own — every request travels over the MCP client's existing authenticated connection.
- **filesystem_access**: `true`
- **filesystem_paths**:
  - **path**: `queries.md` (inside the skill's own bundle)
    **justification**: Read-only reference file shipped with the skill, holding the NRQL templates and attribute-coverage reference. The skill reads no other path and writes nothing.
- **shell_or_code_execution**: `false`
- **code_execution_details**: Not applicable. The skill is Markdown instructions only — it bundles no scripts and instructs no shell, package-manager, download or `eval` step.
- **accesses_secrets**: `false`
- **secrets_accessed**:
  - None. Authentication is handled entirely by the MCP client and the New Relic MCP server's OAuth 2.0 layer. The skill never reads an environment variable, token, or key store. Note separately that credentials can appear *inside the log data it reads* — see the credential-exposure note above.
- **performs_sensitive_actions**: `false`
- **requires_human_confirmation**: `false`
- **actions_requiring_confirmation**:
  - None. Every tool the skill uses is read-only, and the New Relic MCP server exposes no write scope at all, so no deletion, overwrite, send, or other irreversible action is reachable. The skill does put decisions to the user on accuracy grounds rather than consequence: it confirms the resolved entity when the target is genuinely ambiguous, and offers the error-group choice via `AskUserQuestion` when the top candidates are close.

**Least privilege.** `observability:read` is the only scope required. The server advertises
`observability:read`, `offline` and `offline_access`, where the latter two govern refresh tokens
rather than data access, and `openid profile email` on the identity leg. No write scope exists to
request.

### Transparency

- **telemetry**: None emitted by the skill. Skill usage is observable only through the New Relic MCP server's own tool-invocation events described under `data_logging`.
