import { useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { WORKFLOW_WAIT } from "@/lib/generated/constants"
import type { JsonObject } from "@/lib/tool-fields"
import { FieldsEditor } from "@/pages/halon/components/workflow/fields-editor"
import { savedWait, WaitForField, waitError } from "@/pages/halon/components/workflow/wait-for-field"
import type { WorkflowStepKind } from "@/types/serializers"

interface ManualEditorProps {
  idPrefix: string
  kind: WorkflowStepKind | null
  config: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

function withoutWait(config: JsonObject): JsonObject {
  return Object.fromEntries(Object.entries(config).filter(([ key ]) => key !== WORKFLOW_WAIT.KEY))
}

// A Manual step: the task, who does it, the note it collects when it is done, and how long it waits for someone to
// mark it done.
export function ManualEditor({ idPrefix, kind, config, references, disabled, onChange }: ManualEditorProps) {
  const [ values, setValues ] = useState<JsonObject>(() => withoutWait(config))
  const [ wait, setWait ] = useState<number | null>(() => savedWait(config))

  function fieldsChanged(next: JsonObject) {
    setValues(next)
    onChange({ ...next, [WORKFLOW_WAIT.KEY]: wait }, waitError(wait))
  }

  function waitChanged(next: number | null) {
    setWait(next)
    onChange({ ...values, [WORKFLOW_WAIT.KEY]: next }, waitError(next))
  }

  return (
    <div className="space-y-3">
      <FieldsEditor idPrefix={idPrefix} fields={kind?.fields ?? []} values={withoutWait(config)} references={references} disabled={disabled} onChange={fieldsChanged} />
      <WaitForField idPrefix={idPrefix} minutes={wait ?? savedWait(config)} hint="If nobody marks it done by then, the step takes its not done way out."
                    disabled={disabled} onChange={waitChanged} />
    </div>
  )
}
