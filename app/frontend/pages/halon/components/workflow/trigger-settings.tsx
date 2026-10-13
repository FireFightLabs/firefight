import { IconPlus, IconX } from "@tabler/icons-react"
import { type ChangeEvent, useEffect, useMemo, useState } from "react"

import { ToolFields } from "@/components/tool-fields/tool-fields"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { WORKFLOW_EDIT_OPERATIONS, WORKFLOW_INPUT_LIMIT, WORKFLOW_TRIGGER_EDITOR, WORKFLOW_TRIGGER_KEYS } from "@/lib/generated/constants"
import { argumentsState, fieldErrors, jsonObject, type ArgumentsState, type JsonObject } from "@/lib/tool-fields"
import { SuggestionCard } from "@/pages/halon/components/workflow/suggestion-card"
import { conditionDrafts, conditionsError, type ConditionDraft, storedConditions, TriggerConditions } from "@/pages/halon/components/workflow/trigger-conditions"
import { TriggerIcon } from "@/pages/halon/components/workflow/trigger-icon"
import { OnceAtFields } from "@/pages/halon/components/workflows/once-at-fields"
import { ScheduleFields } from "@/pages/halon/components/workflows/schedule-fields"
import type { SendEdit } from "@/pages/halon/hooks/use-workflow-edits"
import { type OnceAt, onceAtFrom, onceAtParams, type Schedule, scheduleFrom, scheduleParams } from "@/pages/halon/lib/schedule"
import type { Trigger } from "@/pages/halon/lib/workflow/types"
import type { WorkflowSuggestion, WorkflowTriggerKind } from "@/types/serializers"

const INPUT_KEY = /^[a-z0-9_]+$/

interface InputDraft {
  key: string
  name: string
  question: string
  defaultValue: string
}

interface TriggerSettingsProps {
  trigger: Trigger
  kind: WorkflowTriggerKind | null
  pending: WorkflowSuggestion[]
  revision: number | null
  timeZones: string[]
  editable: boolean
  send: SendEdit
}

function inputDrafts(trigger: Trigger): InputDraft[] {
  return trigger.inputs.map((input) => ({ key: crypto.randomUUID(), name: input.key, question: input.question, defaultValue: input.default ?? "" }))
}

// The trigger's own settings without its conditions, which have an editor of their own.
function settingsOf(config: JsonObject): JsonObject {
  const rest = { ...config }
  delete rest[WORKFLOW_TRIGGER_KEYS.CONDITIONS]
  return rest
}

function inputsError(inputs: InputDraft[]): string | null {
  if (inputs.some((input) => !INPUT_KEY.test(input.name.trim()))) {
    return "Give each input a key of lowercase letters, numbers and underscores, such as region."
  }
  if (inputs.some((input) => input.question.trim().length === 0)) {
    return "Give each input the question a person is asked."
  }
  const names = inputs.map((input) => input.name.trim())
  return new Set(names).size === names.length ? null : "Give each input a key of its own."
}

// What starts the workflow, and the inputs a person answers when they run it by hand, each with its question and a
// default. Changing it names the draft revision it was made on, as a step's settings do.
export function TriggerSettings({ trigger, kind, pending, revision, timeZones, editable, send }: TriggerSettingsProps) {
  const savedKey = JSON.stringify(trigger)
  const [ inputs, setInputs ] = useState<InputDraft[]>(() => inputDrafts(trigger))
  const [ settings, setSettings ] = useState<ArgumentsState>(() => argumentsState(settingsOf(jsonObject(trigger.config))))
  const [ conditions, setConditions ] = useState<ConditionDraft[]>(() => conditionDrafts(trigger.config[WORKFLOW_TRIGGER_KEYS.CONDITIONS]))
  const [ schedule, setSchedule ] = useState<Schedule>(() => scheduleFrom(trigger.config))
  const [ onceAt, setOnceAt ] = useState<OnceAt>(() => onceAtFrom(trigger.config))
  const editor = kind?.editor ?? WORKFLOW_TRIGGER_EDITOR.NONE
  const [ dirty, setDirty ] = useState(false)
  const [ baseRevision, setBaseRevision ] = useState(revision)

  useEffect(() => {
    if (dirty) {
      return
    }
    const saved: Trigger = JSON.parse(savedKey)
    setInputs(inputDrafts(saved))
    setSettings(argumentsState(settingsOf(jsonObject(saved.config))))
    setConditions(conditionDrafts(saved.config[WORKFLOW_TRIGGER_KEYS.CONDITIONS]))
    setSchedule(scheduleFrom(saved.config))
    setOnceAt(onceAtFrom(saved.config))
    setBaseRevision(revision)
  }, [ savedKey, revision, dirty ])

  const error = useMemo(() => {
    const fieldsWrong = kind && Object.keys(fieldErrors(kind.fields, settings)).length > 0
    return inputsError(inputs) ?? (fieldsWrong ? "Fill in what the trigger needs." : null) ?? conditionsError(conditions)
  }, [ inputs, settings, kind, conditions ])

  function updateInput(key: string, patch: Partial<InputDraft>) {
    setInputs(inputs.map((input) => (input.key === key ? { ...input, ...patch } : input)))
    setDirty(true)
  }

  function typed(key: string, field: "name" | "question" | "defaultValue") {
    return (event: ChangeEvent<HTMLInputElement>) => updateInput(key, { [field]: event.target.value })
  }

  function removeInput(key: string) {
    return () => {
      setInputs(inputs.filter((input) => input.key !== key))
      setDirty(true)
    }
  }

  function addInput() {
    setInputs([ ...inputs, { key: crypto.randomUUID(), name: "", question: "", defaultValue: "" } ])
    setDirty(true)
  }

  function settingsChanged(next: ArgumentsState) {
    setSettings(next)
    setDirty(true)
  }

  function conditionsChanged(next: ConditionDraft[]) {
    setConditions(next)
    setDirty(true)
  }

  function scheduleChanged(next: Schedule) {
    setSchedule(next)
    setDirty(true)
  }

  function onceAtChanged(next: OnceAt) {
    setOnceAt(next)
    setDirty(true)
  }

  // What the kind's own editor holds, written over the settings so a timed trigger keeps only the keys its repeat reads.
  function timed(): JsonObject {
    if (editor === WORKFLOW_TRIGGER_EDITOR.SCHEDULE) {
      return scheduleParams(schedule)
    }
    if (editor === WORKFLOW_TRIGGER_EDITOR.ONCE_AT) {
      return onceAtParams(onceAt)
    }
    if (kind?.event) {
      return { ...jsonObject(settings.values), [WORKFLOW_TRIGGER_KEYS.CONDITIONS]: storedConditions(conditions) }
    }
    return jsonObject(settings.values)
  }

  function discard() {
    setDirty(false)
  }

  function apply() {
    const written: JsonObject = {
      ...timed(),
      [WORKFLOW_TRIGGER_KEYS.KIND]: trigger.kind,
      [WORKFLOW_TRIGGER_KEYS.INPUTS]: inputs.map((input) => ({ key: input.name.trim(), question: input.question.trim(), default: input.defaultValue.trim() || null })),
    }
    send(WORKFLOW_EDIT_OPERATIONS.CHANGE_TRIGGER, { trigger: written }, { baseRevision, onSuccess: discard })
  }

  return (
    <div data-trigger-settings className="flex h-full min-h-0 flex-col">
      <header className="flex items-start gap-2.5 border-b border-border p-3">
        <TriggerIcon icon={trigger.icon} />
        <div className="min-w-0 flex-1">
          <h3 className="text-sm leading-tight font-semibold text-fg-headline">{trigger.label}</h3>
          <p className="mt-1 text-xs text-fg-muted">{kind?.description ?? "What starts a run of this workflow."}</p>
        </div>
      </header>
      <div className="min-h-0 flex-1 space-y-5 overflow-y-auto p-3">
        {pending.map((each) => <SuggestionCard key={each.id} suggestion={each} />)}
        {editor === WORKFLOW_TRIGGER_EDITOR.SCHEDULE && (
          <ScheduleFields idPrefix="trigger-schedule" schedule={schedule} timeZones={timeZones} disabled={!editable} onChange={scheduleChanged} />
        )}
        {editor === WORKFLOW_TRIGGER_EDITOR.ONCE_AT && (
          <OnceAtFields idPrefix="trigger-once" onceAt={onceAt} timeZones={timeZones} disabled={!editable} onChange={onceAtChanged} />
        )}
        {kind && kind.fields.length > 0 && (
          <ToolFields idPrefix="trigger" fields={kind.fields} state={settings} errors={fieldErrors(kind.fields, settings)} placeholders={[]} places={[]}
                      disabled={!editable} onChange={settingsChanged} />
        )}
        {kind?.event && (
          <TriggerConditions idPrefix="trigger-condition" fields={kind.conditions} drafts={conditions} disabled={!editable} onChange={conditionsChanged} />
        )}
        <section className="space-y-2">
          <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">Inputs</h4>

          <p className="text-xs text-fg-muted">What a person is asked when they run it by hand. Steps read each as {"{{inputs.key}}"}.</p>
          {inputs.map((input) => (
            <div key={input.key} className="space-y-1.5 rounded-md border border-border p-2">
              <div className="flex gap-1.5">
                <div className="flex-1 space-y-1">
                  <Label htmlFor={`trigger-input-${input.key}`} className="text-xs">Key</Label>
                  <Input id={`trigger-input-${input.key}`} value={input.name} onChange={typed(input.key, "name")} placeholder="region" disabled={!editable} className="font-mono text-xs" />
                </div>
                {editable && (
                  <button type="button" aria-label={`Remove ${input.name || "this input"}`} className="mt-5 px-1 text-fg-muted hover:text-destructive" onClick={removeInput(input.key)}>
                    <IconX className="size-4" />
                  </button>
                )}
              </div>
              <Input value={input.question} onChange={typed(input.key, "question")} placeholder="Which region?" aria-label="Question" disabled={!editable} />
              <Input value={input.defaultValue} onChange={typed(input.key, "defaultValue")} placeholder="Default (optional)" aria-label="Default" disabled={!editable} />
            </div>
          ))}
          {editable && inputs.length < WORKFLOW_INPUT_LIMIT && (
            <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={addInput}>
              <IconPlus className="size-3.5" />
              Add an input
            </Button>
          )}
        </section>
        {dirty && error && <p className="text-xs text-destructive">{error}</p>}
      </div>
      {editable && (
        <footer className="flex items-center justify-end gap-2 border-t border-border p-3">
          {dirty && <Button type="button" variant="ghost" size="sm" onClick={discard}>Discard changes</Button>}
          <Button type="button" size="sm" disabled={!dirty || error !== null} onClick={apply}>Apply changes</Button>
        </footer>
      )}
    </div>
  )
}
