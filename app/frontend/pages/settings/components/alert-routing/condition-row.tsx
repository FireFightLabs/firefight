import { CONDITION_OPERATORS, type CatalogOptionMap, type ConditionOperator } from "@/pages/settings/lib/alerts"
import { conditionValues, type ConditionRow } from "@/pages/settings/components/alert-routing/rule-form"
import { BadgeMultiSelect } from "@/pages/settings/components/alert-routing/badge-multi-select"
import { RemoveRowButton } from "@/pages/settings/components/row-list-buttons"
import { Input } from "@/components/ui/input"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

export function ConditionRowFields({
  condition,
  catalogOptions,
  onChange,
  onRemove,
}: {
  condition: ConditionRow
  catalogOptions: CatalogOptionMap
  onChange: (patch: Partial<ConditionRow>) => void
  onRemove: () => void
}) {
  const catalog = condition.operator === "is_one_of" ? catalogOptions[condition.field.trim()] : undefined
  const values = conditionValues(condition)

  return (
    <div className="flex items-center gap-2">
      <Input
        value={condition.field}
        onChange={(event) => onChange({ field: event.target.value })}
        placeholder="field, e.g. service"
        className="w-36"
      />
      <Select
        value={condition.operator}
        onValueChange={(value) => onChange({ operator: value as ConditionOperator })}
      >
        <SelectTrigger className="w-36">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {CONDITION_OPERATORS.map((op) => (
            <SelectItem key={op.value} value={op.value}>{op.label}</SelectItem>
          ))}
        </SelectContent>
      </Select>
      {catalog ? (
        <BadgeMultiSelect
          className="flex-1"
          selected={values}
          options={catalog.map((option) => ({ value: option.slug, label: option.name }))}
          placeholder="Add from catalogue…"
          onAdd={(slug) => onChange({ value: [ ...values, slug ].join(", ") })}
          onRemove={(slug) => onChange({ value: values.filter((event) => event !== slug).join(", ") })}
        />
      ) : condition.operator !== "is_empty" && (
        <Input
          value={condition.value}
          onChange={(event) => onChange({ value: event.target.value })}
          placeholder={condition.operator === "is_one_of" ? "comma-separated values" : "value"}
          className="flex-1"
        />
      )}
      <RemoveRowButton label="Remove condition" onClick={onRemove} />
    </div>
  )
}
