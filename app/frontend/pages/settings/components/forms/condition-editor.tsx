import { useState } from "react"
import { IconFilter, IconX } from "@tabler/icons-react"

import type {
  IncidentConditionSettings,
  IncidentFormFieldSettings,
  IncidentFormSettings,
} from "@/pages/settings/lib/types"
import type { IncidentSeveritySettings, IncidentStatusSettings, IncidentTypeSettings } from "@/types/serializers"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Label } from "@/components/ui/label"
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

const CONDITION_FIELD_INCIDENT_TYPE = "incident_type"
const CONDITION_FIELD_SEVERITY = "severity"
const CONDITION_FIELD_STATUS = "status"
const CONDITION_FIELD_VISIBILITY = "visibility"
const CONDITION_FIELD_CUSTOM = "custom_field"

const VISIBILITY_OPTIONS = [
  { id: "public", name: "Everyone (public)" },
  { id: "private", name: "Private" },
]
const OPERATOR_ONE_OF = "one_of"
const OPERATOR_NOT_ONE_OF = "not_one_of"

const OPERATOR_LABELS: Record<string, string> = {
  [OPERATOR_ONE_OF]: "is one of",
  [OPERATOR_NOT_ONE_OF]: "is not one of",
}

// One row per thing a condition can read. Custom fields come from the form,
// which only offers those a responder could already have answered.
interface ConditionSource {
  key: string
  conditionField: string
  definitionId: string | null
  label: string
  options: { id: string; name: string }[]
}

interface ConditionState {
  id: string
  operator: string
  selectedIds: Set<string>
}

function buildSources(
  form: IncidentFormSettings,
  incidentTypes: IncidentTypeSettings[],
  severities: IncidentSeveritySettings[],
  statuses: IncidentStatusSettings[],
): ConditionSource[] {
  const asked = new Set(form.conditionSourceSystemKeys)
  const sources: ConditionSource[] = []

  if (asked.has(CONDITION_FIELD_INCIDENT_TYPE)) {
    sources.push({
      key: CONDITION_FIELD_INCIDENT_TYPE,
      conditionField: CONDITION_FIELD_INCIDENT_TYPE,
      definitionId: null,
      label: "Incident Type",
      options: incidentTypes.map((type) => ({ id: type.id, name: type.name })),
    })
  }

  if (asked.has(CONDITION_FIELD_SEVERITY)) {
    sources.push({
      key: CONDITION_FIELD_SEVERITY,
      conditionField: CONDITION_FIELD_SEVERITY,
      definitionId: null,
      label: "Severity",
      options: severities.map((severity) => ({ id: severity.id, name: severity.name })),
    })
  }

  if (asked.has(CONDITION_FIELD_STATUS)) {
    sources.push({
      key: CONDITION_FIELD_STATUS,
      conditionField: CONDITION_FIELD_STATUS,
      definitionId: null,
      label: "Status",
      options: statuses.map((status) => ({ id: status.id, name: status.name })),
    })
  }

  if (asked.has(CONDITION_FIELD_VISIBILITY)) {
    sources.push({
      key: CONDITION_FIELD_VISIBILITY,
      conditionField: CONDITION_FIELD_VISIBILITY,
      definitionId: null,
      label: "Visibility",
      options: VISIBILITY_OPTIONS,
    })
  }

  form.conditionSources.forEach((definition) => {
    sources.push({
      key: `${CONDITION_FIELD_CUSTOM}:${definition.id}`,
      conditionField: CONDITION_FIELD_CUSTOM,
      definitionId: definition.id,
      label: definition.name,
      options: definition.options,
    })
  })

  return sources
}

function keyForCondition(condition: IncidentConditionSettings): string {
  return condition.conditionField === CONDITION_FIELD_CUSTOM
    ? `${CONDITION_FIELD_CUSTOM}:${condition.incidentFieldDefinitionId}`
    : condition.conditionField
}

function stateFor(conditions: IncidentConditionSettings[] | undefined, source: ConditionSource): ConditionState {
  const match = conditions?.find((condition) => keyForCondition(condition) === source.key)
  return {
    id: match?.id ?? "",
    operator: match?.operator ?? OPERATOR_ONE_OF,
    selectedIds: new Set(match?.values ?? []),
  }
}

function stateBySource(conditions: IncidentConditionSettings[] | undefined, sources: ConditionSource[]) {
  return new Map(sources.map((source) => [source.key, stateFor(conditions, source)]))
}

function conditionSummary(
  conditions: IncidentConditionSettings[],
  sources: ConditionSource[],
): string | null {
  if (!conditions.length) {
    return null
  }

  return conditions
    .map((condition) => {
      const source = sources.find((candidate) => candidate.key === keyForCondition(condition))
      const names = condition.values
        .map((value) => source?.options.find((option) => option.id === value)?.name ?? value)
        .join(", ")
      const operatorLabel = OPERATOR_LABELS[condition.operator] ?? condition.operator
      return `${source?.label ?? condition.conditionField} ${operatorLabel} ${names}`
    })
    .join(" AND ")
}

export function ConditionEditor({ field, form, incidentTypes, severities, statuses, readOnly = false, onSave }: {
  field: IncidentFormFieldSettings
  form: IncidentFormSettings
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  statuses: IncidentStatusSettings[]
  // Shows the saved conditions as plain text with no popover behind them.
  readOnly?: boolean
  onSave: (conditions: IncidentConditionSettings[]) => void
}) {
  const sources = buildSources(form, incidentTypes, severities, statuses)

  const [states, setStates] = useState(() => stateBySource(field.conditions, sources))
  const [open, setOpen] = useState(false)
  const [prevConditions, setPrevConditions] = useState(field.conditions)
  if (field.conditions !== prevConditions) {
    setPrevConditions(field.conditions)
    setStates(stateBySource(field.conditions, sources))
  }

  function updateState(key: string, next: Partial<ConditionState>) {
    setStates((current) => {
      const updated = new Map(current)
      const existing = updated.get(key)
      if (existing) {
        updated.set(key, { ...existing, ...next })
      }
      return updated
    })
  }

  function toggleId(key: string, id: string) {
    const existing = states.get(key)
    if (!existing) {
      return
    }
    const selectedIds = new Set(existing.selectedIds)
    if (selectedIds.has(id)) {
      selectedIds.delete(id)
    }
    else {
      selectedIds.add(id)
    }
    updateState(key, { selectedIds })
  }

  function handleSave() {
    const conditions: IncidentConditionSettings[] = []
    sources.forEach((source) => {
      const state = states.get(source.key)
      if (!state || state.selectedIds.size === 0) {
        return
      }
      conditions.push({
        id: state.id,
        conditionField: source.conditionField,
        incidentFieldDefinitionId: source.definitionId,
        operator: state.operator,
        values: Array.from(state.selectedIds),
      })
    })
    onSave(conditions)
    setOpen(false)
  }

  function handleClear() {
    onSave([])
    setOpen(false)
  }

  const hasConditions = (field.conditions?.length ?? 0) > 0
  const nothingSelected = sources.every((source) => (states.get(source.key)?.selectedIds.size ?? 0) === 0)

  if (readOnly) {
    if (!hasConditions) {
      return null
    }

    return (
      <span className="flex items-center gap-1 rounded-md bg-cyan-500/10 px-2 py-0.5 text-[11px] text-cyan-600 dark:text-cyan-400">
        <IconFilter className="size-3" />
        {conditionSummary(field.conditions!, sources)}
      </span>
    )
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          className={cn(
            "flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px] transition-colors",
            hasConditions
              ? "bg-cyan-500/10 text-cyan-600 dark:text-cyan-400 hover:bg-cyan-500/15"
              : "text-muted-foreground/50 hover:text-muted-foreground hover:bg-muted/30"
          )}
        >
          <IconFilter className="size-3" />
          {hasConditions
            ? conditionSummary(field.conditions!, sources)
            : "Add condition"}
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-96 p-0">
        <div className="max-h-[26rem] space-y-4 overflow-y-auto p-4">
          <p className="text-xs text-muted-foreground">
            Show this field only when all of the following match.
          </p>

          {sources.length === 0 && (
            <p className="py-4 text-center text-xs text-muted-foreground">
              Nothing on this form or the ones before it can drive a condition yet.
            </p>
          )}

          {sources.map((source) => (
            <ConditionSection
              key={source.key}
              label={source.label}
              state={states.get(source.key)!}
              options={source.options}
              onOperatorChange={(operator) => updateState(source.key, { operator })}
              onToggle={(id) => toggleId(source.key, id)}
            />
          ))}
        </div>

        <div className="flex items-center justify-between border-t border-border px-4 py-2.5">
          {hasConditions ? (
            <Button variant="ghost" size="sm" className="h-7 gap-1 px-2 text-xs text-muted-foreground hover:text-destructive" onClick={handleClear}>
              <IconX className="size-3" />
              Remove all
            </Button>
          ) : (
            <div />
          )}
          <Button size="sm" className="h-7 px-3 text-xs" onClick={handleSave} disabled={nothingSelected && !hasConditions}>
            Save
          </Button>
        </div>
      </PopoverContent>
    </Popover>
  )
}

function ConditionSection({
  label,
  state,
  options,
  onOperatorChange,
  onToggle,
}: {
  label: string
  state: ConditionState
  options: { id: string; name: string }[]
  onOperatorChange: (op: string) => void
  onToggle: (id: string) => void
}) {
  return (
    <div className="space-y-2 rounded-md border border-border/60 p-3">
      <div className="flex items-center gap-2">
        <Label className="text-xs font-medium">{label}</Label>
        <Select value={state.operator} onValueChange={onOperatorChange}>
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
        <div className="max-h-40 space-y-1 overflow-y-auto rounded-md border border-border p-2">
          {options.map((option) => (
            <label key={option.id} className="flex cursor-pointer items-center gap-2 rounded px-1.5 py-1 text-xs hover:bg-muted/30">
              <Checkbox
                checked={state.selectedIds.has(option.id)}
                onCheckedChange={() => onToggle(option.id)}
              />
              <span>{option.name}</span>
            </label>
          ))}
          {options.length === 0 && (
            <p className="py-2 text-center text-xs text-muted-foreground">Nothing to choose from yet.</p>
          )}
        </div>
      </div>
    </div>
  )
}
