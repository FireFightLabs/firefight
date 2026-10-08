import { IconPlus, IconX } from "@tabler/icons-react"
import type { ChangeEvent } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import {
  isHistoryRead,
  stepText,
  withStepField,
  type JsonObject,
  type WatchState,
} from "@/pages/settings/lib/runbook-procedure"
import type { RunbookWatchRead } from "@/types/serializers"

interface RunbookWatchEditorProps {
  watch: WatchState
  reads: RunbookWatchRead[] | null
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  errors: { watch: string | null; steps: Record<string, string> }
  serverError: string | null
  onChange: (watch: WatchState) => void
}

// What Halon watches once every step went through: a title, each thing to follow (a run in a resource's history, or a
// reading that says when it is done) and an optional time limit. Anything saved that this does not show is kept.
export function RunbookWatchEditor({ watch, reads, placeholders, places, errors, serverError, onChange }: RunbookWatchEditorProps) {
  const readOptions = (reads ?? []).map((read) => ({ value: read.name, label: read.label }))

  function patch(next: Partial<WatchState>) {
    onChange({ ...watch, ...next })
  }

  function turn(on: boolean) {
    const steps = on && watch.steps.length === 0 ? [ newStep(reads) ] : watch.steps
    patch({ on, steps })
  }

  function setTitle(event: ChangeEvent<HTMLInputElement>) {
    patch({ spec: withStepField(watch.spec, "title", event.target.value) })
  }

  function setMinutes(event: ChangeEvent<HTMLInputElement>) {
    patch({ minutesDraft: event.target.value })
  }

  function setStep(key: string, field: string, entered: string | boolean) {
    patch({ steps: watch.steps.map((step) => (step.key === key ? { ...step, spec: withStepField(step.spec, field, entered) } : step)) })
  }

  function addStep() {
    patch({ steps: [ ...watch.steps, newStep(reads) ] })
  }

  function removeStep(key: string) {
    patch({ steps: watch.steps.filter((step) => step.key !== key) })
  }

  return (
    <div className="space-y-3">
      <div className="flex items-start justify-between gap-4">
        <div className="space-y-1">
          <Label htmlFor="runbook-watch-on">Watch afterwards</Label>
          <p className="text-xs text-muted-foreground">
            Once every step went through, Halon follows these and reports back in the chat and by direct message.
          </p>
        </div>
        <Switch id="runbook-watch-on" checked={watch.on} onCheckedChange={turn} />
      </div>
      {watch.on && (
        <div className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-[1fr_9rem]">
            <div className="space-y-1">
              <Label htmlFor="runbook-watch-title" className="text-xs">What is watched</Label>
              <Input id="runbook-watch-title" value={stepText(watch.spec, "title")} onChange={setTitle} placeholder="release and its deploy" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="runbook-watch-minutes" className="text-xs">Time limit, minutes</Label>
              <Input id="runbook-watch-minutes" inputMode="numeric" value={watch.minutesDraft} onChange={setMinutes} placeholder="Learned" />
            </div>
          </div>
          <p className="text-xs text-muted-foreground">
            Leave the time limit empty and Halon learns it from how long these usually take, up to a day.
          </p>
          {watch.steps.map((step, index) => (
            <WatchStepEditor
              key={step.key}
              number={index + 1}
              spec={step.spec}
              history={isHistoryRead(step.spec, reads ?? [])}
              readOptions={readOptions}
              resourceOptions={[ ...places, ...placeholders ]}
              error={errors.steps[step.key]}
              onChange={(field, entered) => setStep(step.key, field, entered)}
              onRemove={() => removeStep(step.key)}
            />
          ))}
          <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={addStep}>
            <IconPlus className="size-3.5" />
            Add something to watch
          </Button>
        </div>
      )}
      {errors.watch && <p className="text-xs text-destructive">{errors.watch}</p>}
      {serverError && <p className="text-xs text-destructive">{serverError}</p>}
    </div>
  )
}

function newStep(reads: RunbookWatchRead[] | null): { key: string; spec: JsonObject } {
  const first = reads?.[0]?.name
  return { key: crypto.randomUUID(), spec: first ? { capability: first } : {} }
}

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

function WatchStepEditor({ number, spec, history, readOptions, resourceOptions, error, onChange, onRemove }: WatchStepEditorProps) {
  const resource = stepText(spec, "resource")
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
    onChange("report_start", checked)
  }

  return (
    <div className="space-y-2 rounded-md border border-border/60 p-2.5">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium">Watch {number}</span>
        <button type="button" aria-label={`Remove watch ${number}`} className="text-fg-muted hover:text-destructive" onClick={onRemove}>
          <IconX className="size-4" />
        </button>
      </div>
      <Input aria-label={`Watch ${number} label`} value={stepText(spec, "label")} onChange={typed("label")} placeholder="Release run" />
      <div className="grid gap-2 sm:grid-cols-2">
        <SearchableSelect value={stepText(spec, "capability") || null} onValueChange={chosen("capability")} options={readOptions} placeholder="How to check it" />
        <SearchableSelect
          value={resource || null}
          onValueChange={chosen("resource")}
          options={resources}
          placeholder="On which resource"
          searchPlaceholder="Search the map"
          emptyText="Nothing on the map by that name"
        />
      </div>
      {history ? (
        <div className="space-y-2">
          <div className="grid gap-2 sm:grid-cols-2">
            <Input aria-label={`Watch ${number} run name`} value={stepText(spec, "name")} onChange={typed("name")} placeholder="Only runs named, such as release (optional)" />
            <Input aria-label={`Watch ${number} run`} value={stepText(spec, "run")} onChange={typed("run")} placeholder="A run by its number (optional)" />
          </div>
          <div className="flex items-center gap-2">
            <Switch id={`watch-${number}-report-start`} checked={spec.report_start === true} onCheckedChange={reportStart} />
            <Label htmlFor={`watch-${number}-report-start`} className="text-xs font-normal">Also say when it starts</Label>
          </div>
        </div>
      ) : (
        <div className="grid gap-2 sm:grid-cols-2">
          <Input aria-label={`Watch ${number} done when`} value={stepText(spec, "done_when")} onChange={typed("done_when")} placeholder="Done when it reads, such as running" />
          <Input aria-label={`Watch ${number} failed when`} value={stepText(spec, "failed_when")} onChange={typed("failed_when")} placeholder="Failed when it reads, such as crashed" />
          <Input aria-label={`Watch ${number} goal`} className="sm:col-span-2" value={stepText(spec, "goal")} onChange={typed("goal")} placeholder="Or the goal in a sentence, such as web runs the new version" />
        </div>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
