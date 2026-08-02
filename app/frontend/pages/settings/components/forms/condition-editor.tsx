import { useState } from "react"
import { IconFilter, IconX } from "@tabler/icons-react"

import type {
  IncidentConditionSettings,
  IncidentFormFieldSettings,
} from "@/pages/settings/lib/types"
import type { IncidentSeveritySettings, IncidentTypeSettings } from "@/types/serializers"
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
const OPERATOR_ONE_OF = "one_of"
const OPERATOR_NOT_ONE_OF = "not_one_of"

type ConditionField = typeof CONDITION_FIELD_INCIDENT_TYPE | typeof CONDITION_FIELD_SEVERITY

const FIELD_LABELS: Record<ConditionField, string> = {
  [CONDITION_FIELD_INCIDENT_TYPE]: "Incident Type",
  [CONDITION_FIELD_SEVERITY]: "Severity",
}

const OPERATOR_LABELS: Record<string, string> = {
  [OPERATOR_ONE_OF]: "is one of",
  [OPERATOR_NOT_ONE_OF]: "is not one of",
}

interface ConditionState {
  id: string
  operator: string
  selectedIds: Set<string>
}

function stateFromCondition(c: IncidentConditionSettings | undefined): ConditionState {
  return {
    id: c?.id ?? "",
    operator: c?.operator ?? OPERATOR_ONE_OF,
    selectedIds: new Set(c?.values ?? []),
  }
}

function conditionSummary(
  conditions: IncidentConditionSettings[],
  incidentTypes: IncidentTypeSettings[],
  severities: IncidentSeveritySettings[],
): string | null {
  if (!conditions.length) {
    return null
  }

  const typeMap = new Map(incidentTypes.map((t) => [t.id, t.name]))
  const severityMap = new Map(severities.map((s) => [s.id, s.name]))

  return conditions
    .map((c) => {
      const map = c.conditionField === CONDITION_FIELD_SEVERITY ? severityMap : typeMap
      const fieldLabel = FIELD_LABELS[c.conditionField as ConditionField] ?? c.conditionField
      const names = c.values.map((v) => map.get(v) ?? v).join(", ")
      const operatorLabel = OPERATOR_LABELS[c.operator] ?? c.operator
      return `${fieldLabel} ${operatorLabel} ${names}`
    })
    .join(" AND ")
}

export function ConditionEditor({ field, incidentTypes, severities, onSave }: {
  field: IncidentFormFieldSettings
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  onSave: (conditions: IncidentConditionSettings[]) => void
}) {
  const existingType = field.conditions?.find((c) => c.conditionField === CONDITION_FIELD_INCIDENT_TYPE)
  const existingSeverity = field.conditions?.find((c) => c.conditionField === CONDITION_FIELD_SEVERITY)

  const [typeState, setTypeState] = useState<ConditionState>(() => stateFromCondition(existingType))
  const [severityState, setSeverityState] = useState<ConditionState>(() => stateFromCondition(existingSeverity))
  const [open, setOpen] = useState(false)
  const [prevConditions, setPrevConditions] = useState(field.conditions)
  if (field.conditions !== prevConditions) {
    setPrevConditions(field.conditions)
    setTypeState(stateFromCondition(field.conditions?.find((c) => c.conditionField === CONDITION_FIELD_INCIDENT_TYPE)))
    setSeverityState(stateFromCondition(field.conditions?.find((c) => c.conditionField === CONDITION_FIELD_SEVERITY)))
  }

  function toggleId(state: ConditionState, setState: (next: ConditionState) => void, id: string) {
    const next = new Set(state.selectedIds)
    if (next.has(id)) {
      next.delete(id)
    } else {
      next.add(id)
    }
    setState({ ...state, selectedIds: next })
  }

  function setOperator(state: ConditionState, setState: (next: ConditionState) => void, operator: string) {
    setState({ ...state, operator })
  }

  function handleSave() {
    const conditions: IncidentConditionSettings[] = []
    if (typeState.selectedIds.size > 0) {
      conditions.push({
        id: typeState.id,
        conditionField: CONDITION_FIELD_INCIDENT_TYPE,
        operator: typeState.operator,
        values: Array.from(typeState.selectedIds),
      })
    }
    if (severityState.selectedIds.size > 0) {
      conditions.push({
        id: severityState.id,
        conditionField: CONDITION_FIELD_SEVERITY,
        operator: severityState.operator,
        values: Array.from(severityState.selectedIds),
      })
    }
    onSave(conditions)
    setOpen(false)
  }

  function handleClear() {
    onSave([])
    setOpen(false)
  }

  const hasConditions = (field.conditions?.length ?? 0) > 0
  const nothingSelected = typeState.selectedIds.size === 0 && severityState.selectedIds.size === 0

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
            ? conditionSummary(field.conditions!, incidentTypes, severities)
            : "Add condition"}
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-96 p-0">
        <div className="space-y-4 p-4">
          <p className="text-xs text-muted-foreground">
            Show this field only when all of the following match.
          </p>

          <ConditionSection
            label="Incident Type"
            optionsLabel="Types"
            emptyLabel="No incident types defined."
            state={typeState}
            options={incidentTypes.map((t) => ({ id: t.id, name: t.name }))}
            onOperatorChange={(op) => setOperator(typeState, setTypeState, op)}
            onToggle={(id) => toggleId(typeState, setTypeState, id)}
          />

          <ConditionSection
            label="Severity"
            optionsLabel="Severities"
            emptyLabel="No severities defined."
            state={severityState}
            options={severities.map((s) => ({ id: s.id, name: s.name }))}
            onOperatorChange={(op) => setOperator(severityState, setSeverityState, op)}
            onToggle={(id) => toggleId(severityState, setSeverityState, id)}
          />
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
  optionsLabel,
  emptyLabel,
  state,
  options,
  onOperatorChange,
  onToggle,
}: {
  label: string
  optionsLabel: string
  emptyLabel: string
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
        <Label className="text-[11px] font-medium text-muted-foreground">{optionsLabel}</Label>
        <div className="max-h-40 space-y-1 overflow-y-auto rounded-md border border-border p-2">
          {options.map((o) => (
            <label key={o.id} className="flex cursor-pointer items-center gap-2 rounded px-1.5 py-1 text-xs hover:bg-muted/30">
              <Checkbox
                checked={state.selectedIds.has(o.id)}
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
    </div>
  )
}
