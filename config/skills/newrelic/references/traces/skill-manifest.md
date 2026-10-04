# skill-manifest — discover-trace

- **manifest_version**: `"1.0"`

## Identity

- **skill**
  - **name**: `newrelic/discover-trace`
  - **version**: `1.0.0`
  - **description**: Finds distributed trace IDs in New Relic telemetry via NRQL and presents every match for the user to choose from.
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

Model behaviour drifts between versions, so these results are valid for the models and date above
only. Re-run `evals/` when the upstream model version changes, or when a New Relic agent or MCP tool
release could move the attribute-coverage figures this skill relies on.

## Security disclosures

### Input trust & prompt injection

- **processes_untrusted_input**: `true`
- **untrusted_input_sources**:
  - New Relic telemetry rows returned by `execute_nrql_query` — `Span`, `Transaction`, `TransactionError` and `Log`. The skill does not author this content; it is written by the customer's monitored applications and by anyone able to reach them. Attacker-influenceable fields it reads into context include `error.message`, `error.class`, `Log.message`, `request.uri`, span `name`, `entity.name` and `appName`.
  - Account names and IDs returned by `list_available_new_relic_accounts`.

**Mitigation.** `SKILL.md` instructs the model to treat all retrieved telemetry as data rather than
instructions, to quote and flag any value that reads like a directive, and never to let retrieved
text change which tools are called or what is disclosed. Per the EPD Non-Boundary Rule this is a
mitigation and **not** a security boundary — the boundary is the read-only OAuth scope below plus
the customer's own runtime sandbox.

### Data handling

- **handles_sensitive_data**: `true`
- **data_categories**:
  - `pii`
  - `confidential`
- **data_egress**: New Relic MCP server (NerdGraph) over HTTPS — the only destination the skill sends to, and it reaches it only through the MCP client's existing authenticated connection. Telemetry the skill reads additionally enters the agent's model context, so the customer's configured LLM inference provider receives it.
- **third_party_subprocessors**:
  - The customer's configured LLM inference provider — receives every telemetry value the skill reads into context, including trace IDs, error messages, log lines, request URIs, entity and account names, and any `email` values returned by the trace-discovery queries.
- **data_retention**: None by the skill. It writes no files, stores no state, and caches nothing between runs. The New Relic MCP server separately records one tool-invocation event per call — see `data_logging`.
- **data_logging**: None written by the skill. The New Relic MCP server records a tool-invocation event per call containing the invoking user's email and ID, the organization ID, and each tool parameter as `param_<name>` truncated to 100 characters. Parameter keys named exactly `password`, `token`, `key` or `secret` are omitted; `nrql_query` is not, so submitted NRQL text — including literal values in `WHERE` clauses — is recorded. The skill itself reads and logs no credential.

**PII note.** The trace-discovery query templates select `latest(email)` and document `email` as a
filterable attribute, so end-user email addresses can enter context and the model provider's
request payload. The field is client-instrumented and sparsely populated, so its presence varies
by account.

### Privilege & actions

- **oauth_scopes**:
  - `observability:read`
- **mcp_tools**:
  - `execute_nrql_query` — read-only NRQL execution; the skill's only data path.
  - `list_available_new_relic_accounts` — read-only; used only when the user supplies no account ID.
- **network_access**: `true`
- **network_endpoints**:
  - **host**: `<the New Relic MCP server host configured in the customer's MCP client>`
    **port**: `443`
    **justification**: Sole transport for all tool calls. The skill issues no raw HTTP of its own — every request travels over the MCP client's existing authenticated connection.
- **filesystem_access**: `true`
- **filesystem_paths**:
  - **path**: `queries.md` (inside the skill's own bundle)
    **justification**: Read-only reference file shipped with the skill, holding the NRQL query templates. The skill reads no other path and writes nothing.
- **shell_or_code_execution**: `false`
- **code_execution_details**: Not applicable. The skill is Markdown instructions only — it bundles no scripts and instructs no shell, package-manager, download or `eval` step.
- **accesses_secrets**: `false`
- **secrets_accessed**:
  - None. Authentication is handled entirely by the MCP client and the New Relic MCP server's OAuth 2.0 layer. The skill never reads an environment variable, token, or key store.
- **performs_sensitive_actions**: `false`
- **requires_human_confirmation**: `false`
- **actions_requiring_confirmation**:
  - None. Every tool the skill uses is read-only, and the New Relic MCP server exposes no write scope at all, so no deletion, overwrite, send, or other irreversible action is reachable. The skill does pause for user input on accuracy grounds rather than consequence: with no account ID supplied it asks the user to choose one before running any query, and it always presents every candidate trace rather than silently selecting one.

**Least privilege.** `observability:read` is the only scope required. The server advertises
`observability:read`, `offline` and `offline_access`, where the latter two govern refresh tokens
rather than data access, and `openid profile email` on the identity leg. No write scope exists to
request.

### Transparency

- **telemetry**: None emitted by the skill. Skill usage is observable only through the New Relic MCP server's own tool-invocation events described under `data_logging`.
