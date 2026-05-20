import { useEffect, useState } from "react"
import { IconFilter, IconX } from "@tabler/icons-react"

import type {
  IncidentConditionSettings,
  IncidentFormFieldSettings,
} from "@/pages/settings/lib/types"
import type { IncidentTypeSettings } from "@/types/serializers"
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
const OPERATOR_ONE_OF = "one_of"
const OPERATOR_NOT_ONE_OF = "not_one_of"

const OPERATOR_LABELS: Record<string, string> = {
  [OPERATOR_ONE_OF]: "is one of",
  [OPERATOR_NOT_ONE_OF]: "is not one of",
}

function conditionSummary(conditions: IncidentConditionSettings[], incidentTypes: IncidentTypeSettings[]): string | null {
  if (!conditions.length) return null

  const typeMap = new Map(incidentTypes.map((t) => [t.id, t.name]))

  return conditions
    .map((c) => {
      const names = c.values.map((v) => typeMap.get(v) ?? v).join(", ")
      const label = OPERATOR_LABELS[c.operator] ?? c.operator
      return `Type ${label} ${names}`
    })
    .join("; ")
}

export function ConditionEditor({ field, incidentTypes, onSave }: {
  field: IncidentFormFieldSettings
  incidentTypes: IncidentTypeSettings[]
  onSave: (conditions: IncidentConditionSettings[]) => void
}) {
  const existing = field.conditions?.[0]
  const [operator, setOperator] = useState(existing?.operator ?? OPERATOR_ONE_OF)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(
    () => new Set(existing?.values ?? [])
  )
  const [open, setOpen] = useState(false)

  useEffect(() => {
    const current = field.conditions?.[0]
    setOperator(current?.operator ?? OPERATOR_ONE_OF)
    setSelectedIds(new Set(current?.values ?? []))
  }, [field.conditions])

  function toggleType(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
  }

  function handleSave() {
    if (selectedIds.size === 0) {
      onSave([])
    } else {
      onSave([ {
        id: existing?.id ?? "",
        conditionField: CONDITION_FIELD_INCIDENT_TYPE,
        operator,
        values: Array.from(selectedIds),
      } ])
    }
    setOpen(false)
  }

  function handleClear() {
    onSave([])
    setOpen(false)
  }

  const hasConditions = (field.conditions?.length ?? 0) > 0

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
            ? conditionSummary(field.conditions!, incidentTypes)
            : "Add condition"}
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-80 p-0">
        <div className="space-y-3 p-4">
          <div className="space-y-1.5">
            <Label className="text-xs font-medium">Show this field when Incident Type</Label>
            <Select value={operator} onValueChange={setOperator}>
              <SelectTrigger className="h-8 text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={OPERATOR_ONE_OF}>is one of</SelectItem>
                <SelectItem value={OPERATOR_NOT_ONE_OF}>is not one of</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label className="text-xs font-medium">Types</Label>
            <div className="max-h-48 space-y-1 overflow-y-auto rounded-md border border-border p-2">
              {incidentTypes.map((t) => (
                <label key={t.id} className="flex cursor-pointer items-center gap-2 rounded px-1.5 py-1 text-xs hover:bg-muted/30">
                  <Checkbox
                    checked={selectedIds.has(t.id)}
                    onCheckedChange={() => toggleType(t.id)}
                  />
                  <span>{t.name}</span>
                </label>
              ))}
              {incidentTypes.length === 0 && (
                <p className="py-2 text-center text-xs text-muted-foreground">No incident types defined.</p>
              )}
            </div>
          </div>
        </div>

        <div className="flex items-center justify-between border-t border-border px-4 py-2.5">
          {hasConditions ? (
            <Button variant="ghost" size="sm" className="h-7 gap-1 px-2 text-xs text-muted-foreground hover:text-destructive" onClick={handleClear}>
              <IconX className="size-3" />
              Remove
            </Button>
          ) : (
            <div />
          )}
          <Button size="sm" className="h-7 px-3 text-xs" onClick={handleSave} disabled={selectedIds.size === 0 && !hasConditions}>
            Save
          </Button>
        </div>
      </PopoverContent>
    </Popover>
  )
}
