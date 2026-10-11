import type { PolicyRule } from "@/types/serializers"
import { addressAlertSourcePath, alertRoutingSendTestPath, alertRoutingTestPath } from "@/lib/routes"
import { postJson } from "@/lib/http"
import {
  ALERT_CONDITION_OPERATORS,
  ALERT_NORMALIZED_FIELDS,
  ALERT_NOTIFY_TARGETS,
  ALERT_OUTCOME_ACTIONS,
  type AlertConditionOperator,
  type AlertOutcomeAction,
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

// A provider a source can be made for, with how to point it at the source, from the provider's own adapter.
export interface AlertProviderSetup {
  provider: string
  label: string
  steps: string[]
  secretFromProvider: boolean
  // The source's secret is part of its URL, so the page only ever holds the URL masked.
  secretInAddress: boolean
  fieldMapping: boolean
  template: string | null
}

export function providerSetup(providers: AlertProviderSetup[], value: string): AlertProviderSetup | null {
  return providers.find((entry) => entry.provider === value) ?? null
}

// The whole URL of a source whose secret is part of it, fetched on demand so it never ships in page props. Null when the
// server refused or could not be reached.
export async function fetchSourceAddress(sourceId: string): Promise<string | null> {
  try {
    const { ok, data } = await postJson<{ path: string }>(addressAlertSourcePath(sourceId))
    return ok && data ? `${window.location.origin}${data.path}` : null
  } catch {
    return null
  }
}

export function providerLabel(providers: AlertProviderSetup[], value: string): string {
  return providers.find((entry) => entry.provider === value)?.label ?? value
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

// One value for which rule was tested and how it went, so a slow response for
// a rule the user moved on from cannot show against the wrong row.
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

// A sample that satisfies the rule's own conditions, so a per-rule test runs
// the real first-match evaluation.
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

// A regex used verbatim as a value generally won't match itself, so a derived
// sample would mislead.
export function needsCustomSample(conditions: RuleCondition[]): boolean {
  return conditions.some((condition) => condition.operator === "matches_regex")
}

export function describeSample(fields: Record<string, string>): string {
  const pairs = Object.entries(fields).map(([key, value]) => `${key}=${value}`)
  return pairs.length > 0 ? pairs.join(", ") : "an empty alert"
}
