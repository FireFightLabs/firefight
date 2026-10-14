import { useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { WORKFLOW_APPROVAL } from "@/lib/generated/constants"
import type { JsonObject } from "@/lib/tool-fields"
import { FieldsEditor } from "@/pages/halon/components/workflow/fields-editor"
import { conditionDrafts, conditionsError, type ConditionDraft, storedConditions, TriggerConditions } from "@/pages/halon/components/workflow/trigger-conditions"
import type { WorkflowStepKind } from "@/types/serializers"

interface ApprovalEditorProps {
  idPrefix: string
  kind: WorkflowStepKind | null
  config: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

// The settings the field form draws, without the conditions this editor draws itself.
function withoutConditions(config: JsonObject): JsonObject {
  return Object.fromEntries(Object.entries(config).filter(([ key ]) => key !== WORKFLOW_APPROVAL.CONDITIONS))
}

function staleHint(count: number): string {
  return count === 0
    ? "Add a condition the incident must still meet, read again while it waits and when it is approved."
    : "The request is withdrawn once the incident no longer meets every condition."
}

// An Approval step: what approvers decide, who they are, and, when it names an incident, the conditions that incident
// must still meet, read again while it waits and once more when it is approved.
export function ApprovalEditor({ idPrefix, kind, config, references, disabled, onChange }: ApprovalEditorProps) {
  const [ drafts, setDrafts ] = useState<ConditionDraft[]>(() => conditionDrafts(config[WORKFLOW_APPROVAL.CONDITIONS]))
  const [ values, setValues ] = useState<JsonObject>(() => withoutConditions(config))
  const namesIncident = String(values[WORKFLOW_APPROVAL.INCIDENT] ?? "").trim().length > 0

  function send(nextValues: JsonObject, nextDrafts: ConditionDraft[]) {
    const reads = String(nextValues[WORKFLOW_APPROVAL.INCIDENT] ?? "").trim().length > 0
    const kept = reads ? nextDrafts : []
    onChange({ ...nextValues, [WORKFLOW_APPROVAL.CONDITIONS]: storedConditions(kept) }, conditionsError(kept))
  }

  function fieldsChanged(next: JsonObject) {
    setValues(next)
    send(next, drafts)
  }

  function conditionsChanged(next: ConditionDraft[]) {
    setDrafts(next)
    send(values, next)
  }

  return (
    <div className="space-y-3">
      <FieldsEditor idPrefix={idPrefix} fields={kind?.fields ?? []} values={withoutConditions(config)} references={references} disabled={disabled} onChange={fieldsChanged} />
      {namesIncident && (
        <TriggerConditions idPrefix={`${idPrefix}-conditions`} fields={kind?.conditions ?? []} drafts={drafts} disabled={disabled}
                           onChange={conditionsChanged} title="Still true" hint={staleHint} />
      )}
    </div>
  )
}
