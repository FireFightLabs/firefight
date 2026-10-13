import { IconX } from "@tabler/icons-react"
import type { ChangeEvent } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { ReferencePicker } from "@/components/tool-fields/reference-picker"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { WORKFLOW_CONDITION_OPERATOR, WORKFLOW_CONDITION_OPERATORS, type WorkflowConditionOperator } from "@/lib/generated/constants"
import { type ComparisonDraft, isValueless } from "@/pages/halon/lib/workflow/branch-draft"
import { OPERATOR_LABELS } from "@/pages/halon/lib/workflow/labels"

interface ConditionRowProps {
  comparison: ComparisonDraft
  references: SearchableSelectOption[]
  removable: boolean
  disabled: boolean
  onChange: (comparison: ComparisonDraft) => void
  onRemove: () => void
}

// One comparison of a branch's route: what it looks at, how it compares and with what.
export function ConditionRow({ comparison, references, removable, disabled, onChange, onRemove }: ConditionRowProps) {
  function typed(side: "left" | "right") {
    return (event: ChangeEvent<HTMLInputElement>) => onChange({ ...comparison, [side]: event.target.value })
  }

  function insert(side: "left" | "right") {
    return (reference: string) => onChange({ ...comparison, [side]: `${comparison[side]}${reference}` })
  }

  function chooseOperator(value: string) {
    onChange({ ...comparison, operator: WORKFLOW_CONDITION_OPERATORS.find((each) => each === value) ?? comparison.operator })
  }

  const oneOf = comparison.operator === WORKFLOW_CONDITION_OPERATOR.IS_ONE_OF

  return (
    <div className="space-y-1.5 rounded-md border border-border p-2">
      <div className="flex gap-1.5">
        <Input value={comparison.left} onChange={typed("left")} placeholder="{{steps.check.status}}" aria-label="What it looks at" disabled={disabled}
               className="font-mono text-xs" />
        {!disabled && <ReferencePicker references={references} label="Use an earlier value to look at" onPick={insert("left")} />}
        {removable && !disabled && (
          <button type="button" aria-label="Remove this condition" className="px-1 text-fg-muted hover:text-destructive" onClick={onRemove}>
            <IconX className="size-4" />
          </button>
        )}
      </div>
      <Select value={comparison.operator} onValueChange={chooseOperator} disabled={disabled}>
        <SelectTrigger className="w-full" aria-label="How it compares"><SelectValue /></SelectTrigger>
        <SelectContent>
          {WORKFLOW_CONDITION_OPERATORS.map((operator: WorkflowConditionOperator) => (
            <SelectItem key={operator} value={operator}>{OPERATOR_LABELS[operator]}</SelectItem>
          ))}
        </SelectContent>
      </Select>
      {!isValueless(comparison.operator) && (
        <div className="flex gap-1.5">
          <Input value={comparison.right} onChange={typed("right")} placeholder={oneOf ? "Separated by commas" : "yes"} aria-label="What it is compared with"
                 disabled={disabled} className="font-mono text-xs" />
          {!disabled && <ReferencePicker references={references} label="Compare with an earlier value" onPick={insert("right")} />}
        </div>
      )}
    </div>
  )
}
