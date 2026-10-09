import type { SearchableSelectOption } from "@/components/searchable-select"
import { RunbookToolFields } from "@/pages/settings/components/runbooks/runbook-tool-fields"
import type { ArgumentsState } from "@/pages/settings/lib/runbook-procedure"
import type { RunbookToolChoice } from "@/types/serializers"

interface StepToolFieldsProps {
  stepKey: string
  tool: string
  tools: RunbookToolChoice[] | null
  args: ArgumentsState
  errors: Record<string, string>
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  onChange: (args: ArgumentsState) => void
}

export function StepToolFields({ stepKey, tool, tools, args, errors, placeholders, places, onChange }: StepToolFieldsProps) {
  const choice = tools?.find((candidate) => candidate.name === tool) ?? null

  return (
    <div className="space-y-2 rounded-md border border-border/60 px-3 py-2.5">
      {choice && <p className="text-xs text-muted-foreground">{choice.description}</p>}
      {tools && !choice && (
        <p className="text-xs text-muted-foreground">
          {tool} is not among the tools you can use here, so its arguments are kept as they were saved.
        </p>
      )}
      <RunbookToolFields
        idPrefix={`step-${stepKey}`}
        fields={choice?.fields ?? null}
        state={args}
        errors={errors}
        placeholders={placeholders}
        places={places}
        onChange={onChange}
      />
    </div>
  )
}
