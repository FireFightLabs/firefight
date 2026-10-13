import { IconPlus, IconX } from "@tabler/icons-react"
import { type ChangeEvent, useState } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { ReferencePicker } from "@/components/tool-fields/reference-picker"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { WORKFLOW_CONFIG_KEYS } from "@/lib/generated/constants"
import { isObject, written, type JsonObject } from "@/lib/tool-fields"
import type { OtherWorkflow } from "@/pages/halon/lib/workflow/types"

const KEYS = WORKFLOW_CONFIG_KEYS
const INPUT_KEY = /^[a-z0-9_]+$/

interface InputDraft {
  key: string
  name: string
  value: string
}

interface RunWorkflowEditorProps {
  idPrefix: string
  config: JsonObject
  workflows: OtherWorkflow[]
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

function inputDrafts(config: JsonObject): InputDraft[] {
  const saved = config[KEYS.INPUTS]
  return Object.entries(isObject(saved) ? saved : {}).map(([ name, value ]) => ({ key: crypto.randomUUID(), name, value: written(value) }))
}

function runError(workflow: string, inputs: InputDraft[]): string | null {
  if (!workflow) {
    return "Choose the workflow it runs."
  }
  if (inputs.some((input) => !INPUT_KEY.test(input.name.trim()))) {
    return "Name each input in lowercase letters, numbers and underscores, as the workflow it runs asks it."
  }
  return null
}

// Another workflow this one runs, by its name, with the inputs it hands it, each a fixed value or one from an earlier
// step. The run waits for it and takes what it hands back.
export function RunWorkflowEditor({ idPrefix, config, workflows, references, disabled, onChange }: RunWorkflowEditorProps) {
  const [ workflow, setWorkflow ] = useState(() => (typeof config[KEYS.WORKFLOW] === "string" ? String(config[KEYS.WORKFLOW]) : ""))
  const [ inputs, setInputs ] = useState<InputDraft[]>(() => inputDrafts(config))
  const known = workflows.some((each) => each.slug === workflow)
  const options = [
    ...(workflow && !known ? [ { value: workflow, label: workflow } ] : []),
    ...workflows.map((each) => ({ value: each.slug, label: each.name })),
  ]

  function send(nextWorkflow: string, nextInputs: InputDraft[]) {
    const handed = Object.fromEntries(nextInputs.filter((input) => input.name.trim()).map((input) => [ input.name.trim(), input.value ]))
    onChange({ ...config, [KEYS.WORKFLOW]: nextWorkflow, [KEYS.INPUTS]: handed }, runError(nextWorkflow, nextInputs))
  }

  function chooseWorkflow(value: string | null) {
    setWorkflow(value ?? "")
    send(value ?? "", inputs)
  }

  function updateInput(key: string, patch: Partial<InputDraft>) {
    const next = inputs.map((input) => (input.key === key ? { ...input, ...patch } : input))
    setInputs(next)
    send(workflow, next)
  }

  function typed(key: string, field: "name" | "value") {
    return (event: ChangeEvent<HTMLInputElement>) => updateInput(key, { [field]: event.target.value })
  }

  function inserted(input: InputDraft) {
    return (reference: string) => updateInput(input.key, { value: `${input.value}${reference}` })
  }

  function removeInput(key: string) {
    return () => {
      const next = inputs.filter((input) => input.key !== key)
      setInputs(next)
      send(workflow, next)
    }
  }

  function addInput() {
    setInputs([ ...inputs, { key: crypto.randomUUID(), name: "", value: "" } ])
  }

  const error = runError(workflow, inputs)

  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-workflow`} className="text-xs">Workflow it runs</Label>
        <SearchableSelect id={`${idPrefix}-workflow`} value={workflow || null} onValueChange={chooseWorkflow} options={options} placeholder="Choose a workflow"
                          searchPlaceholder="Search workflows" emptyText="No other workflow by that name" disabled={disabled} />
      </div>
      <div className="space-y-1.5">
        <Label className="text-xs">Inputs it hands on</Label>
        {inputs.length === 0 && <p className="text-xs text-fg-muted">None. The workflow it runs uses its own defaults.</p>}
        {inputs.map((input) => (
          <div key={input.key} className="flex gap-1.5">
            <Input value={input.name} onChange={typed(input.key, "name")} placeholder="region" aria-label="Input" disabled={disabled} className="w-28 font-mono text-xs" />
            <Input value={input.value} onChange={typed(input.key, "value")} placeholder="eu-west-1" aria-label={`Value of ${input.name || "the input"}`}
                   disabled={disabled} className="font-mono text-xs" />
            {!disabled && <ReferencePicker references={references} label="Hand on an earlier value" onPick={inserted(input)} />}
            {!disabled && (
              <button type="button" aria-label={`Remove ${input.name || "this input"}`} className="px-1 text-fg-muted hover:text-destructive" onClick={removeInput(input.key)}>
                <IconX className="size-4" />
              </button>
            )}
          </div>
        ))}
        {!disabled && (
          <Button type="button" variant="ghost" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={addInput}>
            <IconPlus className="size-3.5" />
            Add an input
          </Button>
        )}
      </div>
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
