import { IconX } from "@tabler/icons-react"
import type { ChangeEvent } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { WATCH_SPEC_KEYS } from "@/lib/generated/constants"
import { stepText, type JsonObject } from "@/pages/settings/lib/runbook-procedure"

interface WatchStepEditorProps {
  number: number
  spec: JsonObject
  history: boolean
  readOptions: SearchableSelectOption[]
  resourceOptions: SearchableSelectOption[]
  error: string | undefined
  onChange: (field: string, entered: string | boolean) => void
  onRemove: () => void
}

export function WatchStepEditor({ number, spec, history, readOptions, resourceOptions, error, onChange, onRemove }: WatchStepEditorProps) {
  const resource = stepText(spec, WATCH_SPEC_KEYS.RESOURCE)
  const resources = resource && !resourceOptions.some((option) => option.value === resource)
    ? [ { value: resource, label: resource }, ...resourceOptions ]
    : resourceOptions

  function typed(field: string) {
    return (event: ChangeEvent<HTMLInputElement>) => onChange(field, event.target.value)
  }

  function chosen(field: string) {
    return (value: string | null) => onChange(field, value ?? "")
  }

  function reportStart(checked: boolean) {
    onChange(WATCH_SPEC_KEYS.REPORT_START, checked)
  }

  return (
    <div className="space-y-2 rounded-md border border-border/60 p-2.5">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium">Watch {number}</span>
        <button type="button" aria-label={`Remove watch ${number}`} className="text-fg-muted hover:text-destructive" onClick={onRemove}>
          <IconX className="size-4" />
        </button>
      </div>
      <Input aria-label={`Watch ${number} label`} value={stepText(spec, WATCH_SPEC_KEYS.LABEL)} onChange={typed(WATCH_SPEC_KEYS.LABEL)} placeholder="Release run" />
      <div className="grid gap-2 sm:grid-cols-2">
        <SearchableSelect value={stepText(spec, WATCH_SPEC_KEYS.CAPABILITY) || null} onValueChange={chosen(WATCH_SPEC_KEYS.CAPABILITY)} options={readOptions} placeholder="How to check it" />
        <SearchableSelect
          value={resource || null}
          onValueChange={chosen(WATCH_SPEC_KEYS.RESOURCE)}
          options={resources}
          placeholder="On which resource"
          searchPlaceholder="Search the map"
          emptyText="Nothing on the map by that name"
        />
      </div>
      {history ? (
        <div className="space-y-2">
          <div className="grid gap-2 sm:grid-cols-2">
            <Input aria-label={`Watch ${number} run name`} value={stepText(spec, WATCH_SPEC_KEYS.NAME)} onChange={typed(WATCH_SPEC_KEYS.NAME)} placeholder="Only runs named, such as release (optional)" />
            <Input aria-label={`Watch ${number} run`} value={stepText(spec, WATCH_SPEC_KEYS.RUN)} onChange={typed(WATCH_SPEC_KEYS.RUN)} placeholder="A run by its number (optional)" />
          </div>
          <div className="flex items-center gap-2">
            <Switch id={`watch-${number}-report-start`} checked={spec[WATCH_SPEC_KEYS.REPORT_START] === true} onCheckedChange={reportStart} />
            <Label htmlFor={`watch-${number}-report-start`} className="text-xs font-normal">Also say when it starts</Label>
          </div>
        </div>
      ) : (
        <div className="grid gap-2 sm:grid-cols-2">
          <Input aria-label={`Watch ${number} done when`} value={stepText(spec, WATCH_SPEC_KEYS.DONE_WHEN)} onChange={typed(WATCH_SPEC_KEYS.DONE_WHEN)} placeholder="Done when it reads, such as running" />
          <Input aria-label={`Watch ${number} failed when`} value={stepText(spec, WATCH_SPEC_KEYS.FAILED_WHEN)} onChange={typed(WATCH_SPEC_KEYS.FAILED_WHEN)} placeholder="Failed when it reads, such as crashed" />
          <Input aria-label={`Watch ${number} goal`} className="sm:col-span-2" value={stepText(spec, WATCH_SPEC_KEYS.GOAL)} onChange={typed(WATCH_SPEC_KEYS.GOAL)} placeholder="Or the goal in a sentence, such as web runs the new version" />
        </div>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
