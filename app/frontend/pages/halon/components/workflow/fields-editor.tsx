import { useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { ToolFields } from "@/components/tool-fields/tool-fields"
import { argumentsState, fieldErrors, REFERENCE, type ArgumentsState, type JsonObject, type ToolField } from "@/lib/tool-fields"
import { useCanvasChoices } from "@/pages/halon/hooks/use-canvas-choices"

interface FieldsEditorProps {
  idPrefix: string
  fields: ToolField[]
  values: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (values: JsonObject) => void
}

// A step's settings drawn from its fields with the same form a runbook step's tool uses, each text field offering the
// values earlier steps hand on.
export function FieldsEditor({ idPrefix, fields, values, references, disabled, onChange }: FieldsEditorProps) {
  const [ state, setState ] = useState<ArgumentsState>(() => argumentsState(values))
  const { places } = useCanvasChoices()

  function changed(next: ArgumentsState) {
    setState(next)
    onChange(next.values)
  }

  return (
    <ToolFields
      idPrefix={idPrefix}
      fields={fields}
      state={state}
      errors={fieldErrors(fields, state, REFERENCE)}
      placeholders={references}
      places={places}
      references={references}
      placeholderPattern={REFERENCE}
      disabled={disabled}
      onChange={changed}
    />
  )
}
