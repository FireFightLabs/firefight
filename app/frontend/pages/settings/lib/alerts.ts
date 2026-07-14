export const CONDITION_OPERATORS = [
  { value: "is_one_of", label: "is one of" },
  { value: "contains", label: "contains" },
  { value: "starts_with", label: "starts with" },
  { value: "matches_regex", label: "matches regex" },
  { value: "is_empty", label: "is empty" },
] as const

export type ConditionOperator = (typeof CONDITION_OPERATORS)[number]["value"]

export const OUTCOME_ACTIONS = [
  { value: "auto_create_incident", label: "Create incident" },
  { value: "attach_to_incident", label: "Attach to open incident" },
  { value: "notify_only", label: "Notify only" },
  { value: "drop", label: "Drop" },
] as const

export type OutcomeAction = (typeof OUTCOME_ACTIONS)[number]["value"]

export const ACTION_LABELS: Record<string, string> = Object.fromEntries(
  OUTCOME_ACTIONS.map((action) => [action.value, action.label])
)

export const TARGET_MEMBER = "member"
export const TARGET_TEAM = "team"
export const TARGET_OWNING_TEAM = "owning_team"
export const TARGET_CHANNEL = "channel"

export const PROVIDER_LABELS: Record<string, string> = {
  generic: "Generic webhook",
  northflank: "Northflank",
}

export interface RuleCondition {
  field: string
  operator: ConditionOperator
  value?: string | string[]
}

export type CatalogOptionMap = Record<string, { slug: string; name: string }[]>

export interface SlackChannel {
  id: string
  name: string
}

export interface TraceCondition {
  field: string
  operator: string
  actual: string | null
  matched: boolean
}

export interface TraceEntry {
  rule_id: string
  priority: number
  matched: boolean
  skipped?: boolean
  conditions: TraceCondition[]
}

export interface TestResult {
  matched: boolean
  outcome: { action?: string } | null
  trace: TraceEntry[]
  resolution?: { invite: string[]; notify: string | null; notes: string[] } | null
}

export interface SendTestResult {
  sent?: boolean
  notify?: string | null
  error?: string
}

export interface RunTestOutcome {
  result: TestResult | null
  error: string | null
}

// Derive a sample alert that should satisfy a rule's own conditions, so a
// per-rule test exercises the real first-match evaluation with plausible input.
export function sampleFieldsFor(conditions: RuleCondition[]): Record<string, string> {
  const fields: Record<string, string> = {}
  for (const condition of conditions) {
    if (condition.operator === "is_empty") continue
    const value = Array.isArray(condition.value) ? condition.value[0] : condition.value
    if (value) fields[condition.field] = value
  }
  return fields
}

// A regex pattern used verbatim as a field value generally won't match itself,
// so a derived sample would mislead; those rules need the custom tester.
export function needsCustomSample(conditions: RuleCondition[]): boolean {
  return conditions.some((condition) => condition.operator === "matches_regex")
}

export function describeSample(fields: Record<string, string>): string {
  const pairs = Object.entries(fields).map(([key, value]) => `${key}=${value}`)
  return pairs.length > 0 ? pairs.join(", ") : "an empty alert"
}

export function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
}
