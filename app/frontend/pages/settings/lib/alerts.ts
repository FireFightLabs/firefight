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

export function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
}
