# skill-manifest — nl2-nrql

- **manifest_version**: `"1.0"`

## Identity

- **skill**
  - **name**: `newrelic/nl2-nrql`
  - **version**: `1.0.0`
  - **description**: Turns a plain-English question about New Relic data into one schema-validated NRQL query, discovering the account's real event types and attributes before generating it.
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
  - Schema metadata returned by `execute_nrql_query` during discovery — `SHOW EVENT TYPES` output, `keyset()` column names, and `uniques()` attribute values. Event-type and attribute names are partly customer-defined (custom events and custom attributes), and `uniques()` returns stored values verbatim, so both are content the skill did not author.
  - Sampled telemetry rows read to confirm formats and units.
  - Account names and IDs returned by `list_available_new_relic_accounts`.

**Mitigation.** `SKILL.md` instructs the model to treat discovery output as data rather than
instructions, and never to let a column name or stored value redirect which tools are called or
what is disclosed. Per the EPD Non-Boundary Rule this is a mitigation and **not** a security
boundary — the boundary is the read-only OAuth scope below plus the customer's own runtime sandbox.

### Data handling

- **handles_sensitive_data**: `true`
- **data_categories**:
  - `pii`
  - `confidential`
- **data_egress**: New Relic MCP server (NerdGraph) over HTTPS — the only destination the skill sends to, and it reaches it only through the MCP client's existing authenticated connection. Schema metadata and sampled rows the skill reads additionally enter the agent's model context, so the customer's configured LLM inference provider receives them.
- **third_party_subprocessors**:
  - The customer's configured LLM inference provider — receives the event types, attribute names, sampled rows and `uniques()` value lists that discovery returns.
- **data_retention**: None by the skill. It writes no files, stores no state, and caches nothing between runs. The New Relic MCP server separately records one tool-invocation event per call — see `data_logging`.
- **data_logging**: None written by the skill. The New Relic MCP server records a tool-invocation event per call containing the invoking user's email and ID, the organization ID, and each tool parameter as `param_<name>` truncated to 100 characters. Parameter keys named exactly `password`, `token`, `key` or `secret` are omitted; `nrql_query` is not, so both the discovery queries and the generated query — including literal values in `WHERE` clauses — are recorded. The skill itself reads and logs no credential.

**PII note.** `pii` is listed because it is reachable, not because the skill targets it. Discovery
samples real attribute values and runs `uniques()` on any attribute headed into a `WHERE` clause,
so if the account carries personal data in an attribute relevant to the user's question — an email,
username or customer identifier — those values enter context. Which attributes are touched depends
entirely on what is asked.

### Privilege & actions

- **oauth_scopes**:
  - `observability:read`
- **mcp_tools**:
  - `execute_nrql_query` — read-only; used for schema discovery and once more to prove the finished query parses.
  - `list_available_new_relic_accounts` — read-only; called only if the user cannot name an account, since it can return several hundred rows.
  - `convert_time_period_to_epoch_ms` — read-only; resolves absolute, timezone-bearing or compound time ranges to epoch bounds.
- **network_access**: `true`
- **network_endpoints**:
  - **host**: `<the New Relic MCP server host configured in the customer's MCP client>`
    **port**: `443`
    **justification**: Sole transport for all tool calls. The skill issues no raw HTTP of its own — every request travels over the MCP client's existing authenticated connection.
- **filesystem_access**: `true`
- **filesystem_paths**:
  - **path**: `queries.md` (inside the skill's own bundle)
    **justification**: Read-only reference file shipped with the skill, holding the aggregator-function reference and time-resolution response shape. The skill reads no other path and writes nothing.
- **shell_or_code_execution**: `false`
- **code_execution_details**: Not applicable. The skill is Markdown instructions only — it bundles no scripts and instructs no shell, package-manager, download or `eval` step. The NRQL it generates is a read-only query language executed by New Relic, not code run on the customer's machine.
- **accesses_secrets**: `false`
- **secrets_accessed**:
  - None. Authentication is handled entirely by the MCP client and the New Relic MCP server's OAuth 2.0 layer. The skill never reads an environment variable, token, or key store.
- **performs_sensitive_actions**: `false`
- **requires_human_confirmation**: `false`
- **actions_requiring_confirmation**:
  - None. Every tool the skill uses is read-only, and the New Relic MCP server exposes no write scope at all, so no deletion, overwrite, send, or other irreversible action is reachable. The skill does stop for user input on accuracy grounds rather than consequence: it refuses to generate anything until the account ID, the question, and the time range are all settled, and it emits no query when discovery finds no event type that can answer the question.

**Least privilege.** `observability:read` is the only scope required. The server advertises
`observability:read`, `offline` and `offline_access`, where the latter two govern refresh tokens
rather than data access, and `openid profile email` on the identity leg. No write scope exists to
request.

### Transparency

- **telemetry**: None emitted by the skill. Skill usage is observable only through the New Relic MCP server's own tool-invocation events described under `data_logging`.
