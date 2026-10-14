import { useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { WORKFLOW_APPROVAL, WORKFLOW_WAIT } from "@/lib/generated/constants"
import type { JsonObject } from "@/lib/tool-fields"
import { FieldsEditor } from "@/pages/halon/components/workflow/fields-editor"
import { conditionDrafts, conditionsError, type ConditionDraft, storedConditions, TriggerConditions } from "@/pages/halon/components/workflow/trigger-conditions"
import { savedWait, WaitForField, waitError } from "@/pages/halon/components/workflow/wait-for-field"
import type { WorkflowStepKind } from "@/types/serializers"

interface ApprovalEditorProps {
  idPrefix: string
  kind: WorkflowStepKind | null
  config: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

// The settings this editor draws itself, kept out of the field form.
const OWN_KEYS: string[] = [ WORKFLOW_APPROVAL.CONDITIONS, WORKFLOW_WAIT.KEY ]

function withoutOwn(config: JsonObject): JsonObject {
  return Object.fromEntries(Object.entries(config).filter(([ key ]) => !OWN_KEYS.includes(key)))
}

function staleHint(count: number): string {
  return count === 0
    ? "Add a condition the incident must still meet, read again while it waits and when it is approved."
    : "The request is withdrawn once the incident no longer meets every condition."
}

interface ApprovalDraft {
  values: JsonObject
  conditions: ConditionDraft[]
  wait: number | null
}

// An Approval step: what approvers decide, who they are, how long it waits for a decision, and, when it names an
// incident, the conditions that incident must still meet, read again while it waits and once more when it is approved.
export function ApprovalEditor({ idPrefix, kind, config, references, disabled, onChange }: ApprovalEditorProps) {
  const [ draft, setDraft ] = useState<ApprovalDraft>(() => ({
    values: withoutOwn(config), conditions: conditionDrafts(config[WORKFLOW_APPROVAL.CONDITIONS]), wait: savedWait(config),
  }))
  const namesIncident = String(draft.values[WORKFLOW_APPROVAL.INCIDENT] ?? "").trim().length > 0

  function send(next: ApprovalDraft) {
    setDraft(next)
    const reads = String(next.values[WORKFLOW_APPROVAL.INCIDENT] ?? "").trim().length > 0
    const kept = reads ? next.conditions : []
    onChange({ ...next.values, [WORKFLOW_APPROVAL.CONDITIONS]: storedConditions(kept), [WORKFLOW_WAIT.KEY]: next.wait }, conditionsError(kept) ?? waitError(next.wait))
  }

  function fieldsChanged(values: JsonObject) {
    send({ ...draft, values })
  }

  function conditionsChanged(conditions: ConditionDraft[]) {
    send({ ...draft, conditions })
  }

  function waitChanged(wait: number | null) {
    send({ ...draft, wait })
  }

  return (
    <div className="space-y-3">
      <FieldsEditor idPrefix={idPrefix} fields={kind?.fields ?? []} values={withoutOwn(config)} references={references} disabled={disabled} onChange={fieldsChanged} />
      <WaitForField idPrefix={idPrefix} minutes={draft.wait ?? savedWait(config)} hint="If nobody decides by then, the request is withdrawn and the step takes its withdrawn way out."
                    disabled={disabled} onChange={waitChanged} />
      {namesIncident && (
        <TriggerConditions idPrefix={`${idPrefix}-conditions`} fields={kind?.conditions ?? []} drafts={draft.conditions} disabled={disabled}
                           onChange={conditionsChanged} title="Still true" hint={staleHint} />
      )}
    </div>
  )
}
