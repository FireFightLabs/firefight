import { IconPlus, IconTrash } from "@tabler/icons-react"

import type {
  IncidentSeveritySettings,
  IncidentTypeSettings,
  RunbookCustomField,
} from "@/types/serializers"
import {
  OPERATOR_NOT_ONE_OF,
  OPERATOR_ONE_OF,
  valueOptions,
} from "@/pages/settings/lib/runbook-conditions"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

export interface ConditionSectionState {
  operator: string
  selectedIds: string[]
}

export interface CustomFieldConditionState {
  key: string
  fieldDefinitionId: string
  operator: string
  selectedIds: string[]
}

export function RunbookConditionsEditor({
  typeState,
  severityState,
  customFieldStates,
  incidentTypes,
  severities,
  customFields,
  onTypeChange,
  onSeverityChange,
  onCustomFieldStatesChange,
}: {
  typeState: ConditionSectionState
  severityState: ConditionSectionState
  customFieldStates: CustomFieldConditionState[]
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  customFields: RunbookCustomField[]
  onTypeChange: (state: ConditionSectionState) => void
  onSeverityChange: (state: ConditionSectionState) => void
  onCustomFieldStatesChange: (states: CustomFieldConditionState[]) => void
}) {
  function addCustomField(fieldDefinitionId: string) {
    onCustomFieldStatesChange([
      ...customFieldStates,
      { key: crypto.randomUUID(), fieldDefinitionId, operator: OPERATOR_ONE_OF, selectedIds: [] },
    ])
  }

  function updateCustomField(key: string, next: Partial<CustomFieldConditionState>) {
    onCustomFieldStatesChange(
      customFieldStates.map((s) => (s.key === key ? { ...s, ...next } : s)),
    )
  }

  function removeCustomField(key: string) {
    onCustomFieldStatesChange(customFieldStates.filter((s) => s.key !== key))
  }

  return (
    <div className="space-y-2">
      <Label>Conditions</Label>
      <p className="text-xs text-muted-foreground">
        Surface this runbook only on incidents that match all of the following. Leave empty to always show it.
      </p>

      <ConditionSection
        label="Incident Type"
        optionsLabel="Types"
        emptyLabel="No incident types defined."
        state={typeState}
        options={incidentTypes.map((t) => ({ id: t.id, name: t.name }))}
        onChange={onTypeChange}
      />

      <ConditionSection
        label="Severity"
        optionsLabel="Severities"
        emptyLabel="No severities defined."
        state={severityState}
        options={severities.map((s) => ({ id: s.id, name: s.name }))}
        onChange={onSeverityChange}
      />

      {customFieldStates.map((state) => {
        const field = customFields.find((f) => f.id === state.fieldDefinitionId)
        if (!field) return null

        return (
          <CustomFieldConditionRow
            key={state.key}
            field={field}
            state={state}
            onChange={(next) => updateCustomField(state.key, next)}
            onRemove={() => removeCustomField(state.key)}
          />
        )
      })}

      {customFields.length > 0 && (
        <Select value="" onValueChange={addCustomField}>
          <SelectTrigger className="h-8 w-full text-xs">
            <span className="flex items-center gap-1.5 text-muted-foreground">
              <IconPlus className="size-3.5" />
              Add custom field condition
            </span>
          </SelectTrigger>
          <SelectContent>
            {customFields.map((f) => (
              <SelectItem key={f.id} value={f.id}>{f.name}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      )}
    </div>
  )
}

function ConditionSection({
  label,
  optionsLabel,
  emptyLabel,
  state,
  options,
  onChange,
}: {
  label: string
  optionsLabel: string
  emptyLabel: string
  state: ConditionSectionState
  options: { id: string; name: string }[]
  onChange: (state: ConditionSectionState) => void
}) {
  function toggle(id: string) {
    const selectedIds = state.selectedIds.includes(id)
      ? state.selectedIds.filter((v) => v !== id)
      : [...state.selectedIds, id]
    onChange({ ...state, selectedIds })
  }

  return (
    <div className="space-y-2 rounded-md border border-border/60 p-3">
      <div className="flex items-center gap-2">
        <Label className="text-xs font-medium">{label}</Label>
        <Select value={state.operator} onValueChange={(operator) => onChange({ ...state, operator })}>
          <SelectTrigger className="h-7 flex-1 text-xs">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={OPERATOR_ONE_OF}>is one of</SelectItem>
            <SelectItem value={OPERATOR_NOT_ONE_OF}>is not one of</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <OptionList
        label={optionsLabel}
        emptyLabel={emptyLabel}
        options={options}
        selectedIds={state.selectedIds}
        onToggle={toggle}
      />
    </div>
  )
}

function CustomFieldConditionRow({
  field,
  state,
  onChange,
  onRemove,
}: {
  field: RunbookCustomField
  state: CustomFieldConditionState
  onChange: (next: Partial<CustomFieldConditionState>) => void
  onRemove: () => void
}) {
  const options = valueOptions(field)

  function toggle(id: string) {
    const selectedIds = state.selectedIds.includes(id)
      ? state.selectedIds.filter((v) => v !== id)
      : [...state.selectedIds, id]
    onChange({ selectedIds })
  }

  return (
    <div className="space-y-2 rounded-md border border-border/60 p-3">
      <div className="flex items-center gap-2">
        <Label className="text-xs font-medium">{field.name}</Label>
        <Select value={state.operator} onValueChange={(operator) => onChange({ operator })}>
          <SelectTrigger className="h-7 flex-1 text-xs">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={OPERATOR_ONE_OF}>is one of</SelectItem>
            <SelectItem value={OPERATOR_NOT_ONE_OF}>is not one of</SelectItem>
          </SelectContent>
        </Select>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="size-7 shrink-0 text-muted-foreground"
          onClick={onRemove}
        >
          <IconTrash className="size-3.5" />
        </Button>
      </div>

      <OptionList
        label="Values"
        emptyLabel="No values available."
        options={options}
        selectedIds={state.selectedIds}
        onToggle={toggle}
      />
    </div>
  )
}

function OptionList({
  label,
  emptyLabel,
  options,
  selectedIds,
  onToggle,
}: {
  label: string
  emptyLabel: string
  options: { id: string; name: string }[]
  selectedIds: string[]
  onToggle: (id: string) => void
}) {
  return (
    <div className="space-y-1">
      <Label className="text-[11px] font-medium text-muted-foreground">{label}</Label>
      <div className="max-h-40 space-y-1 overflow-y-auto rounded-md border border-border p-2">
        {options.map((o) => (
          <label key={o.id} className="flex cursor-pointer items-center gap-2 rounded px-1.5 py-1 text-xs hover:bg-muted/30">
            <Checkbox
              checked={selectedIds.includes(o.id)}
              onCheckedChange={() => onToggle(o.id)}
            />
            <span>{o.name}</span>
          </label>
        ))}
        {options.length === 0 && (
          <p className="py-2 text-center text-xs text-muted-foreground">{emptyLabel}</p>
        )}
      </div>
    </div>
  )
}
