import { IconPlus } from "@tabler/icons-react"
import type { ChangeEvent } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { WATCH_SPEC_KEYS } from "@/lib/generated/constants"
import { WatchStepEditor } from "@/pages/settings/components/runbooks/watch-step-editor"
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
  error: string | null
  serverErrors: string[]
  onChange: (watch: WatchState) => void
}

// What Halon watches once every step went through: a title, each thing to follow (a run in a resource's history, or a
// reading that says when it is done) and an optional time limit. Anything saved that this does not show is kept.
export function RunbookWatchEditor({ watch, reads, placeholders, places, error, serverErrors, onChange }: RunbookWatchEditorProps) {
  const readOptions = (reads ?? []).map((read) => ({ value: read.name, label: read.label }))

  function patch(next: Partial<WatchState>) {
    onChange({ ...watch, ...next })
  }

  function turn(on: boolean) {
    const steps = on && watch.steps.length === 0 ? [ newStep(reads) ] : watch.steps
    patch({ on, steps })
  }

  function setTitle(event: ChangeEvent<HTMLInputElement>) {
    patch({ spec: withStepField(watch.spec, WATCH_SPEC_KEYS.TITLE, event.target.value) })
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
              <Input id="runbook-watch-title" value={stepText(watch.spec, WATCH_SPEC_KEYS.TITLE)} onChange={setTitle} placeholder="release and its deploy" />
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
      {error && <p className="text-xs text-destructive">{error}</p>}
      {serverErrors.map((sentence, index) => (
        <p key={index} className="text-xs text-destructive">{sentence}</p>
      ))}
    </div>
  )
}

function newStep(reads: RunbookWatchRead[] | null): { key: string; spec: JsonObject } {
  const first = reads?.[0]?.name
  return { key: crypto.randomUUID(), spec: first ? { [WATCH_SPEC_KEYS.CAPABILITY]: first } : {} }
}
