import { IconPlus } from "@tabler/icons-react"
import type { ChangeEvent } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { WatchStepEditor } from "@/components/watch/watch-step-editor"
import { WATCH_SPEC_KEYS } from "@/lib/generated/constants"
import type { ArgumentsState } from "@/lib/tool-fields"
import {
  firstWatchStep,
  isHistoryRead,
  readOf,
  stepText,
  waitsName,
  withNewDeploy,
  withNewDeployField,
  withRead,
  withStepField,
  type WatchState,
  type WatchStepState,
  type WatchTool,
} from "@/lib/watch-spec"
import type { RunbookWatchRead } from "@/types/serializers"

interface WatchSpecEditorProps {
  idPrefix: string
  watch: WatchState
  reads: RunbookWatchRead[] | null
  tools: WatchTool[] | null
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  disabled?: boolean
  onChange: (watch: WatchState) => void
}

// What a watch follows: a title, each thing to follow (a run in a resource's history, a reading of a resource, or any
// read tool Halon can make in a chat, with what counts as done) and an optional time limit. A runbook's watch afterwards
// and a workflow's Watch step are both written here. Anything saved that this does not show is kept.
export function WatchSpecEditor({ idPrefix, watch, reads, tools, placeholders, places, disabled = false, onChange }: WatchSpecEditorProps) {
  const capabilityNames = new Set((reads ?? []).map((read) => read.name))
  const readTools = (tools ?? []).filter((tool) => tool.reads && !capabilityNames.has(tool.name))
  const readOptions = [
    ...(reads ?? []).map((read) => ({ value: read.name, label: read.label, group: "Anything on the resource map" })),
    ...readTools.map((tool) => ({ value: tool.name, label: tool.name, group: tool.group })),
  ]

  function patch(next: Partial<WatchState>) {
    onChange({ ...watch, ...next })
  }

  function setTitle(event: ChangeEvent<HTMLInputElement>) {
    patch({ spec: withStepField(watch.spec, WATCH_SPEC_KEYS.TITLE, event.target.value) })
  }

  function setMinutes(event: ChangeEvent<HTMLInputElement>) {
    patch({ minutesDraft: event.target.value })
  }

  function changeStep(key: string, change: (step: WatchStepState) => WatchStepState) {
    patch({ steps: watch.steps.map((step) => (step.key === key ? change(step) : step)) })
  }

  function setStep(key: string, field: string, entered: string | boolean) {
    changeStep(key, (step) => ({ ...step, spec: withStepField(step.spec, field, entered) }))
  }

  function chooseRead(key: string, name: string) {
    changeStep(key, (step) => withRead(step, name, capabilityNames.has(name)))
  }

  function setArgs(key: string, args: ArgumentsState) {
    changeStep(key, (step) => ({ ...step, args }))
  }

  function setWaits(key: string, waitsFor: string[], keptWaits: string[]) {
    changeStep(key, (step) => ({ ...step, waitsFor, keptWaits }))
  }

  function turnNewDeploy(key: string, on: boolean) {
    changeStep(key, (step) => ({ ...step, spec: withNewDeploy(step.spec, on) }))
  }

  function setNewDeploy(key: string, field: string, entered: string) {
    changeStep(key, (step) => ({ ...step, spec: withNewDeployField(step.spec, field, entered) }))
  }

  function addStep() {
    patch({ steps: [ ...watch.steps, firstWatchStep(reads) ] })
  }

  function removeStep(key: string) {
    patch({ steps: watch.steps.filter((step) => step.key !== key) })
  }

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-[1fr_9rem]">
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-title`} className="text-xs">What is watched</Label>
          <Input id={`${idPrefix}-title`} value={stepText(watch.spec, WATCH_SPEC_KEYS.TITLE)} onChange={setTitle} placeholder="release and its deploy" disabled={disabled} />
        </div>
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-minutes`} className="text-xs">Time limit, minutes</Label>
          <Input id={`${idPrefix}-minutes`} inputMode="numeric" value={watch.minutesDraft} onChange={setMinutes} placeholder="Learned" disabled={disabled} />
        </div>
      </div>
      <p className="text-xs text-muted-foreground">
        Leave the time limit empty and Halon learns it from how long these usually take, up to a day.
      </p>
      {watch.steps.map((step, index) => (
        <WatchStepEditor
          key={step.key}
          number={index + 1}
          step={step}
          earlier={watch.steps.slice(0, index).map((each, at) => ({ value: each.key, label: waitsName(each, at) }))}
          history={isHistoryRead(step.spec, reads ?? [])}
          tool={readTools.find((tool) => tool.name === stepText(step.spec, WATCH_SPEC_KEYS.TOOL)) ?? null}
          toolsLoaded={tools !== null}
          readOptions={readOptions}
          selectedRead={readOf(step.spec)}
          resourceOptions={[ ...places, ...placeholders ]}
          placeholders={placeholders}
          places={places}
          disabled={disabled}
          onChange={(field, entered) => setStep(step.key, field, entered)}
          onChooseRead={(name) => chooseRead(step.key, name)}
          onArgsChange={(args) => setArgs(step.key, args)}
          onWaitsChange={(waitsFor, keptWaits) => setWaits(step.key, waitsFor, keptWaits)}
          onNewDeployTurn={(on) => turnNewDeploy(step.key, on)}
          onNewDeployChange={(field, entered) => setNewDeploy(step.key, field, entered)}
          onRemove={() => removeStep(step.key)}
        />
      ))}
      {!disabled && (
        <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={addStep}>
          <IconPlus className="size-3.5" />
          Add something to watch
        </Button>
      )}
    </div>
  )
}
