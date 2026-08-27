import type { PolicyRule } from "@/types/serializers"
import { alertRoutingSendTestPath, alertRoutingTestPath } from "@/lib/routes"
import { postJson } from "@/lib/http"
import {
  ALERT_CONDITION_OPERATORS,
  ALERT_NORMALIZED_FIELDS,
  ALERT_NOTIFY_TARGETS,
  ALERT_OUTCOME_ACTIONS,
  ALERT_PROVIDERS,
  type AlertConditionOperator,
  type AlertOutcomeAction,
  type AlertProvider,
} from "@/lib/generated/constants"

export type ConditionOperator = AlertConditionOperator
export type OutcomeAction = AlertOutcomeAction

const OPERATOR_LABELS: Record<ConditionOperator, string> = {
  is_one_of: "is one of",
  contains: "contains",
  starts_with: "starts with",
  matches_regex: "matches regex",
  is_empty: "is empty",
}

export const CONDITION_OPERATORS = ALERT_CONDITION_OPERATORS.map((value) => ({ value, label: OPERATOR_LABELS[value] }))

export const ACTION_LABELS: Record<OutcomeAction, string> = {
  auto_create_incident: "Create incident",
  attach_to_incident: "Attach to open incident",
  notify_only: "Notify only",
  drop: "Drop",
}

export const OUTCOME_ACTIONS = ALERT_OUTCOME_ACTIONS.map((value) => ({ value, label: ACTION_LABELS[value] }))

function isOutcomeAction(value: string): value is OutcomeAction {
  return (ALERT_OUTCOME_ACTIONS as readonly string[]).includes(value)
}

// For values that arrive as plain strings from a serializer.
export function actionLabel(value: string): string {
  return isOutcomeAction(value) ? ACTION_LABELS[value] : value
}

export const TARGET_MEMBER = ALERT_NOTIFY_TARGETS.MEMBER
export const TARGET_TEAM = ALERT_NOTIFY_TARGETS.TEAM
export const TARGET_OWNING_TEAM = ALERT_NOTIFY_TARGETS.OWNING_TEAM
export const TARGET_CHANNEL = ALERT_NOTIFY_TARGETS.CHANNEL

export const PROVIDER_LABELS: Record<AlertProvider, string> = {
  generic: "Generic webhook",
  northflank: "Northflank",
}

function isAlertProvider(value: string): value is AlertProvider {
  return (ALERT_PROVIDERS as readonly string[]).includes(value)
}

export function providerLabel(value: string): string {
  return isAlertProvider(value) ? PROVIDER_LABELS[value] : value
}

export const NORMALIZED_FIELDS = ALERT_NORMALIZED_FIELDS

export type RuleCondition = PolicyRule["conditions"][number]

export type CatalogOptionMap = Record<string, { slug: string; name: string }[]>

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

// One value for "which rule was tested and how did it go", so a slow
// response for a rule the user has since moved on from cannot be shown
// against the wrong row.
export type RuleTest =
  | { status: "pending"; ruleId: string; sample: string }
  | { status: "done"; ruleId: string; sample: string; result: TestResult }
  | { status: "failed"; ruleId: string; sample: string; error: string }

export interface SendTestResult {
  sent?: boolean
  notify?: string | null
  error?: string
}

export async function runRoutingTest(
  fields: Record<string, string>,
  alertSourceId: string | null
): Promise<{ result: TestResult | null; error: string | null }> {
  const fallback = "The test request failed; try again."
  try {
    const { ok, data } = await postJson<TestResult>(alertRoutingTestPath(), { fields, alert_source_id: alertSourceId })
    if (!ok || !data) {
      return { result: null, error: (data as { error?: string } | null)?.error ?? fallback }
    }
    return { result: data, error: null }
  } catch {
    return { result: null, error: fallback }
  }
}

export async function sendRoutingTest(
  fields: Record<string, string>,
  alertSourceId: string | null
): Promise<SendTestResult> {
  try {
    const { data } = await postJson<SendTestResult>(alertRoutingSendTestPath(), { fields, alert_source_id: alertSourceId })
    return data ?? { error: "The request failed; try again." }
  } catch {
    return { error: "The request failed; try again." }
  }
}

// Derive a sample alert that should satisfy a rule's own conditions, so a
// per-rule test exercises the real first-match evaluation with plausible input.
export function sampleFieldsFor(conditions: RuleCondition[]): Record<string, string> {
  const fields: Record<string, string> = {}
  for (const condition of conditions) {
    if (condition.operator === "is_empty") {
      continue
    }
    const value = Array.isArray(condition.value) ? condition.value[0] : condition.value
    if (value) {
      fields[condition.field] = value
    }
  }
  return fields
}

// A regex pattern used verbatim as a field value generally won't match itself,
// so a derived sample would mislead. Those rules need the custom tester.
export function needsCustomSample(conditions: RuleCondition[]): boolean {
  return conditions.some((condition) => condition.operator === "matches_regex")
}

export function describeSample(fields: Record<string, string>): string {
  const pairs = Object.entries(fields).map(([key, value]) => `${key}=${value}`)
  return pairs.length > 0 ? pairs.join(", ") : "an empty alert"
}
