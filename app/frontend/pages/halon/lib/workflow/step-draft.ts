import {
  WORKFLOW_BODY_KEYS,
  WORKFLOW_KINDS,
  WORKFLOW_MAX_ATTEMPTS,
  WORKFLOW_ON_FAILURE_CHOICE,
  type WorkflowBackoff,
  type WorkflowOnFailure,
} from "@/lib/generated/constants"
import { jsonObject, jsonValue, type JsonObject } from "@/lib/tool-fields"
import type { WorkflowStepNode } from "@/types/serializers"

// A step's errors and retries as their fields hold them, words while they are typed.
export interface FailureDraft {
  maxAttempts: string
  backoff: WorkflowBackoff | ""
  backoffSeconds: string
  timeoutSeconds: string
  onFailure: WorkflowOnFailure
}

export interface StepDraft {
  config: JsonObject
  failure: FailureDraft
}

const WHOLE = /^\s*\d+\s*$/
// The engine's own retry count when a step sets none.
export const DEFAULT_ATTEMPTS = 5

export function failureDraft(step: WorkflowStepNode): FailureDraft {
  const settings = step.retrySettings
  return {
    maxAttempts: settings?.max_attempts == null ? "" : String(settings.max_attempts),
    backoff: settings?.backoff ?? "",
    backoffSeconds: settings?.backoff_seconds == null ? "" : String(settings.backoff_seconds),
    timeoutSeconds: step.timeoutSeconds == null ? "" : String(step.timeoutSeconds),
    onFailure: step.onFailure ?? WORKFLOW_ON_FAILURE_CHOICE.STOP,
  }
}

export function stepDraft(step: WorkflowStepNode): StepDraft {
  return { config: jsonObject(step.config), failure: failureDraft(step) }
}

// What is wrong with the errors and retries, by field, before anything is sent.
export function failureErrors(failure: FailureDraft, kind: string): Partial<Record<keyof FailureDraft, string>> {
  const errors: Partial<Record<keyof FailureDraft, string>> = {}
  const attempts = failure.maxAttempts.trim()
  if (attempts && (!WHOLE.test(attempts) || Number(attempts) < 1 || Number(attempts) > WORKFLOW_MAX_ATTEMPTS)) {
    errors.maxAttempts = `A whole number from 1 to ${WORKFLOW_MAX_ATTEMPTS}.`
  }
  const timeout = failure.timeoutSeconds.trim()
  if (timeout && (!WHOLE.test(timeout) || Number(timeout) < 1)) {
    errors.timeoutSeconds = "A whole number of seconds above zero."
  }
  if (!timeout && kind === WORKFLOW_KINDS.WAIT_FOR_EVENT) {
    errors.timeoutSeconds = "Waiting for an event needs a time limit, since the event may never come."
  }
  const seconds = failure.backoffSeconds.trim()
  if (seconds && (!WHOLE.test(seconds) || Number(seconds) < 1)) {
    errors.backoffSeconds = "A whole number of seconds above zero."
  }
  return errors
}

function sameJson(first: unknown, second: unknown): boolean {
  return JSON.stringify(first) === JSON.stringify(second)
}

function retryOf(failure: FailureDraft): JsonObject | null {
  const retry: JsonObject = {}
  if (failure.maxAttempts.trim()) {
    retry.max_attempts = Number(failure.maxAttempts)
  }
  if (failure.backoff) {
    retry.backoff = failure.backoff
  }
  if (failure.backoffSeconds.trim()) {
    retry.backoff_seconds = Number(failure.backoffSeconds)
  }
  return Object.keys(retry).length > 0 ? retry : null
}

// The change_config changes that turn the step as saved into the draft: the config keys that changed, a key that went
// sent as empty so the server drops it, and each setting that moved.
export function draftChanges(step: WorkflowStepNode, draft: StepDraft): JsonObject {
  const changes: JsonObject = {}
  const saved = jsonObject(step.config)
  const config: JsonObject = {}
  // The inside of a for each changes by its own edits on the canvas, never from its settings.
  const body: readonly string[] = step.kind === WORKFLOW_KINDS.FOR_EACH ? WORKFLOW_BODY_KEYS : []
  for (const [ key, value ] of Object.entries(draft.config)) {
    if (!body.includes(key) && !sameJson(saved[key], value)) {
      config[key] = jsonValue(value)
    }
  }
  for (const key of Object.keys(saved)) {
    if (!body.includes(key) && !(key in draft.config)) {
      config[key] = null
    }
  }
  if (Object.keys(config).length > 0) {
    changes.config = config
  }
  const timeout = draft.failure.timeoutSeconds.trim() ? Number(draft.failure.timeoutSeconds) : null
  if (timeout !== (step.timeoutSeconds ?? null)) {
    changes.timeout_seconds = timeout
  }
  const retry = retryOf(draft.failure)
  if (!sameJson(retry, step.retrySettings ?? null)) {
    changes.retry = retry
  }
  const stopsByDefault = (choice: WorkflowOnFailure | undefined) => (choice === WORKFLOW_ON_FAILURE_CHOICE.STOP ? null : choice ?? null)
  const onFailure = stopsByDefault(draft.failure.onFailure)
  if (onFailure !== stopsByDefault(step.onFailure)) {
    changes.on_failure = onFailure
  }
  return changes
}
