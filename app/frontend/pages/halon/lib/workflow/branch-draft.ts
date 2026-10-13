import {
  WORKFLOW_CONDITION_JOINS,
  WORKFLOW_CONDITION_OPERATOR,
  WORKFLOW_CONDITION_OPERATORS,
  WORKFLOW_CONFIG_KEYS,
  WORKFLOW_CONDITION_VALUELESS,
  type WorkflowConditionOperator,
} from "@/lib/generated/constants"
import { isObject, jsonValue, type JsonObject } from "@/lib/tool-fields"

type Join = (typeof WORKFLOW_CONDITION_JOINS)[keyof typeof WORKFLOW_CONDITION_JOINS]

export interface ComparisonDraft {
  key: string
  left: string
  operator: WorkflowConditionOperator
  right: string
}

// One route of a branch: its name and the conditions that take it, all of them or any. A condition written in a shape
// the editor cannot show, such as one with not, is kept as it was.
export interface RouteDraft {
  key: string
  route: string
  join: Join
  comparisons: ComparisonDraft[]
  kept: JsonObject | null
}

export interface BranchDraft {
  routes: RouteDraft[]
  otherwise: string
}

const ROUTE_NAME = /^[a-z][a-z0-9_]{0,63}$/
const VALUELESS: readonly string[] = WORKFLOW_CONDITION_VALUELESS

function operatorOf(value: unknown): WorkflowConditionOperator {
  return WORKFLOW_CONDITION_OPERATORS.find((operator) => operator === value) ?? WORKFLOW_CONDITION_OPERATORS[0]
}

function text(value: unknown): string {
  if (value === undefined || value === null) {
    return ""
  }
  return Array.isArray(value) ? value.map(String).join(", ") : String(value)
}

export function emptyComparison(): ComparisonDraft {
  return { key: crypto.randomUUID(), left: "", operator: WORKFLOW_CONDITION_OPERATORS[0], right: "" }
}

const KEYS = WORKFLOW_CONFIG_KEYS

function comparison(condition: JsonObject): ComparisonDraft | null {
  if (!(KEYS.OPERATOR in condition) || !(KEYS.LEFT in condition)) {
    return null
  }
  return { key: crypto.randomUUID(), left: text(condition[KEYS.LEFT]), operator: operatorOf(condition[KEYS.OPERATOR]), right: text(condition[KEYS.RIGHT]) }
}

function routeDraft(saved: unknown): RouteDraft {
  const route = isObject(saved) ? saved : {}
  const condition = route[KEYS.WHEN]
  const when = isObject(condition) ? condition : null
  const base = { key: crypto.randomUUID(), route: text(route[KEYS.ROUTE]), join: WORKFLOW_CONDITION_JOINS.ALL, comparisons: [], kept: null }
  if (!when) {
    return { ...base, comparisons: [ emptyComparison() ] }
  }
  const single = comparison(when)
  if (single) {
    return { ...base, comparisons: [ single ] }
  }
  for (const join of [ WORKFLOW_CONDITION_JOINS.ALL, WORKFLOW_CONDITION_JOINS.ANY ]) {
    const list = when[join]
    if (Array.isArray(list)) {
      const comparisons = list.map((each) => (isObject(each) ? comparison(each) : null))
      if (comparisons.every((each) => each !== null) && comparisons.length > 0) {
        return { ...base, join, comparisons: comparisons.filter((each) => each !== null) }
      }
    }
  }
  return { ...base, kept: when }
}

export function branchDraft(config: JsonObject): BranchDraft {
  const saved = config[KEYS.ROUTES]
  const routes = Array.isArray(saved) ? saved.map(routeDraft) : []
  return { routes, otherwise: text(config[KEYS.OTHERWISE]) }
}

function written(draft: ComparisonDraft): JsonObject {
  const condition: JsonObject = { [KEYS.LEFT]: draft.left, [KEYS.OPERATOR]: draft.operator }
  if (VALUELESS.includes(draft.operator)) {
    return condition
  }
  const oneOf = draft.operator === WORKFLOW_CONDITION_OPERATOR.IS_ONE_OF
  condition[KEYS.RIGHT] = oneOf ? draft.right.split(",").map((part) => part.trim()).filter((part) => part.length > 0) : draft.right
  return condition
}

// The branch's config as the engine reads it: each route with its condition, one comparison as it is and several under
// all or any, and the otherwise route when one is named.
export function branchConfig(draft: BranchDraft): JsonObject {
  const routes = draft.routes.map((route) => {
    const when = route.kept ?? (route.comparisons.length === 1 ? written(route.comparisons[0]) : { [route.join]: route.comparisons.map(written) })
    return { [KEYS.ROUTE]: route.route.trim(), [KEYS.WHEN]: jsonValue(when) }
  })
  return { [KEYS.ROUTES]: routes, [KEYS.OTHERWISE]: draft.otherwise.trim() || null }
}

// What is wrong with the routes, as one sentence, before anything is sent.
export function branchError(draft: BranchDraft): string | null {
  if (draft.routes.length === 0) {
    return "A branch needs at least one route."
  }
  const names = draft.routes.map((route) => route.route.trim())
  if (draft.otherwise.trim()) {
    names.push(draft.otherwise.trim())
  }
  if (names.some((name) => !ROUTE_NAME.test(name))) {
    return "Name each route in lowercase letters, numbers and underscores, starting with a letter, such as yes or too_slow."
  }
  if (new Set(names).size !== names.length) {
    return "Give each route a name of its own."
  }
  if (draft.routes.some((route) => !route.kept && route.comparisons.some((each) => each.left.trim().length === 0))) {
    return "Say what each condition looks at, such as {{steps.check.status}}."
  }
  return null
}

export function isValueless(operator: WorkflowConditionOperator): boolean {
  return VALUELESS.includes(operator)
}
