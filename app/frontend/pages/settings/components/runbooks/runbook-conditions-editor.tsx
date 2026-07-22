import type { IncidentSeveritySettings, IncidentTypeSettings } from "@/types/serializers"
import { OPERATOR_NOT_ONE_OF, OPERATOR_ONE_OF } from "@/pages/settings/lib/runbook-conditions"
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

export function RunbookConditionsEditor({
  typeState,
  severityState,
  incidentTypes,
  severities,
  onTypeChange,
  onSeverityChange,
}: {
  typeState: ConditionSectionState
  severityState: ConditionSectionState
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  onTypeChange: (state: ConditionSectionState) => void
  onSeverityChange: (state: ConditionSectionState) => void
}) {
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

      <div className="space-y-1">
        <Label className="text-[11px] font-medium text-muted-foreground">{optionsLabel}</Label>
        <div className="max-h-40 space-y-1 overflow-y-auto rounded-md border border-border p-2">
          {options.map((o) => (
            <label key={o.id} className="flex cursor-pointer items-center gap-2 rounded px-1.5 py-1 text-xs hover:bg-muted/30">
              <Checkbox
                checked={state.selectedIds.includes(o.id)}
                onCheckedChange={() => toggle(o.id)}
              />
              <span>{o.name}</span>
            </label>
          ))}
          {options.length === 0 && (
            <p className="py-2 text-center text-xs text-muted-foreground">{emptyLabel}</p>
          )}
        </div>
      </div>
    </div>
  )
}
