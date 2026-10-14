import type { ChangeEvent } from "react"

import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  WORKFLOW_BACKOFF,
  WORKFLOW_BACKOFFS,
  WORKFLOW_ON_FAILURE,
  WORKFLOW_ON_FAILURE_CHOICE,
  type WorkflowBackoff,
  type WorkflowOnFailure,
} from "@/lib/generated/constants"
import { BACKOFF_LABELS, ON_FAILURE_LABELS } from "@/pages/halon/lib/workflow/labels"
import { DEFAULT_ATTEMPTS, type FailureDraft } from "@/pages/halon/lib/workflow/step-draft"

const SAME_AS_ENGINE = "default"

interface FailureSettingsProps {
  idPrefix: string
  failure: FailureDraft
  errors: Partial<Record<keyof FailureDraft, string>>
  // The step waits on a person for as long as its own settings say, so it has no time limit here.
  waits: boolean
  disabled: boolean
  onChange: (failure: FailureDraft) => void
}

// What a step does when it fails: how many times it is tried and how long it waits between tries, how long one try may
// take, and whether the run stops, carries on or takes the step's error path.
export function FailureSettings({ idPrefix, failure, errors, waits, disabled, onChange }: FailureSettingsProps) {
  function typed(field: "maxAttempts" | "backoffSeconds" | "timeoutSeconds") {
    return (event: ChangeEvent<HTMLInputElement>) => onChange({ ...failure, [field]: event.target.value })
  }

  function chooseBackoff(value: string) {
    const backoff = WORKFLOW_BACKOFFS.find((each) => each === value) ?? ""
    onChange({ ...failure, backoff })
  }

  function chooseOnFailure(value: string) {
    onChange({ ...failure, onFailure: WORKFLOW_ON_FAILURE.find((each) => each === value) ?? WORKFLOW_ON_FAILURE_CHOICE.STOP })
  }

  return (
    <section className="space-y-3">
      <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">Errors and retries</h4>
      <div className="grid grid-cols-2 gap-2.5">
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-attempts`} className="text-xs">Tries</Label>
          <Input id={`${idPrefix}-attempts`} inputMode="numeric" value={failure.maxAttempts} onChange={typed("maxAttempts")} placeholder={String(DEFAULT_ATTEMPTS)}
                 disabled={disabled} aria-invalid={errors.maxAttempts != null} />
          {errors.maxAttempts && <p className="text-xs text-destructive">{errors.maxAttempts}</p>}
        </div>
        {!waits && (
          <div className="space-y-1">
            <Label htmlFor={`${idPrefix}-timeout`} className="text-xs">Time limit in seconds</Label>
            <Input id={`${idPrefix}-timeout`} inputMode="numeric" value={failure.timeoutSeconds} onChange={typed("timeoutSeconds")} placeholder="None"
                   disabled={disabled} aria-invalid={errors.timeoutSeconds != null} />
            {errors.timeoutSeconds && <p className="text-xs text-destructive">{errors.timeoutSeconds}</p>}
          </div>
        )}
      </div>
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-backoff`} className="text-xs">Wait between tries</Label>
        <Select value={failure.backoff || SAME_AS_ENGINE} onValueChange={chooseBackoff} disabled={disabled}>
          <SelectTrigger id={`${idPrefix}-backoff`} className="w-full"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={SAME_AS_ENGINE}>{BACKOFF_LABELS[WORKFLOW_BACKOFF.EXPONENTIAL]}, the default</SelectItem>
            {WORKFLOW_BACKOFFS.map((backoff: WorkflowBackoff) => <SelectItem key={backoff} value={backoff}>{BACKOFF_LABELS[backoff]}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      {failure.backoff === WORKFLOW_BACKOFF.FIXED && (
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-backoff-seconds`} className="text-xs">Seconds between tries</Label>
          <Input id={`${idPrefix}-backoff-seconds`} inputMode="numeric" value={failure.backoffSeconds} onChange={typed("backoffSeconds")} placeholder="60"
                 disabled={disabled} aria-invalid={errors.backoffSeconds != null} />
          {errors.backoffSeconds && <p className="text-xs text-destructive">{errors.backoffSeconds}</p>}
        </div>
      )}
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-on-failure`} className="text-xs">When every try fails</Label>
        <Select value={failure.onFailure} onValueChange={chooseOnFailure} disabled={disabled}>
          <SelectTrigger id={`${idPrefix}-on-failure`} className="w-full"><SelectValue /></SelectTrigger>
          <SelectContent>
            {WORKFLOW_ON_FAILURE.map((choice: WorkflowOnFailure) => <SelectItem key={choice} value={choice}>{ON_FAILURE_LABELS[choice]}</SelectItem>)}
          </SelectContent>
        </Select>
        {failure.onFailure === WORKFLOW_ON_FAILURE_CHOICE.ERROR_ROUTE && (
          <p className="text-xs text-fg-muted">Connect the step&apos;s error way out to what should happen next.</p>
        )}
      </div>
    </section>
  )
}
