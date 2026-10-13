import { BadgeMultiSelect } from "@/components/badge-multi-select"
import type { ToolField } from "@/lib/tool-fields"

interface ChoiceListInputProps {
  field: ToolField
  selected: string[]
  disabled: boolean
  onChange: (field: ToolField, entered: string) => void
}

function choiceLabel(value: string): string {
  const words = value.split("_").join(" ")
  return words.charAt(0).toUpperCase() + words.slice(1)
}

// A list field whose values come from a fixed set, such as which changes start a trigger: each chosen one as a badge,
// and the rest offered to add.
export function ChoiceListInput({ field, selected, disabled, onChange }: ChoiceListInputProps) {
  const options = field.options.map((option) => ({ value: option, label: choiceLabel(option) }))

  function added(value: string) {
    onChange(field, [ ...selected, value ].join(", "))
  }

  function removed(value: string) {
    onChange(field, selected.filter((each) => each !== value).join(", "))
  }

  if (disabled) {
    return <p className="text-sm text-fg-body">{selected.map(choiceLabel).join(", ") || "None"}</p>
  }

  return <BadgeMultiSelect stacked selected={selected} options={options} placeholder="Add one" onAdd={added} onRemove={removed} />
}
