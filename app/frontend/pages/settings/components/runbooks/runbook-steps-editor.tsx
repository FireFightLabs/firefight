import {
  IconChevronDown,
  IconChevronUp,
  IconGripVertical,
  IconPlus,
  IconX,
} from "@tabler/icons-react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { RunbookToolFields } from "@/pages/settings/components/runbooks/runbook-tool-fields"
import { emptyArguments, type ArgumentsState } from "@/pages/settings/lib/runbook-procedure"
import type { RunbookToolChoice } from "@/types/serializers"

export interface EditableStep {
  key: string
  id?: string
  title: string
  instruction: string
  // The tool Halon runs the step with, by the name Halon calls it, or empty for a step a person does.
  tool: string
  args: ArgumentsState
}

// A step with no tool is one a person does, as every incident runbook step was before.
const BY_HAND = ""

interface RunbookStepsEditorProps {
  steps: EditableStep[]
  // What is wrong with each step's fields, by the step's key and then the field's.
  stepErrors: Record<string, Record<string, string>>
  // null while the editor's choices load.
  tools: RunbookToolChoice[] | null
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  onChange: (steps: EditableStep[]) => void
}

export function RunbookStepsEditor({ steps, stepErrors, tools, placeholders, places, onChange }: RunbookStepsEditorProps) {
  const toolOptions: SearchableSelectOption[] = [
    { value: BY_HAND, label: "None, a person does this step" },
    ...(tools ?? []).map((tool) => ({ value: tool.name, label: tool.name, group: tool.group })),
  ]

  function chooseTool(index: number, tool: string | null) {
    update(index, { tool: tool ?? BY_HAND, args: emptyArguments() })
  }

  function update(index: number, patch: Partial<EditableStep>) {
    onChange(steps.map((step, position) => (position === index ? { ...step, ...patch } : step)))
  }

  function add() {
    onChange([...steps, { key: crypto.randomUUID(), title: "", instruction: "", tool: BY_HAND, args: emptyArguments() }])
  }

  function remove(index: number) {
    onChange(steps.filter((_, event) => event !== index))
  }

  function move(index: number, direction: -1 | 1) {
    const target = index + direction
    if (target < 0 || target >= steps.length) {
      return
    }
    const next = [...steps]
    ;[next[index], next[target]] = [next[target], next[index]]
    onChange(next)
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <Label>Steps</Label>
        <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={add}>
          <IconPlus className="size-3.5" />
          Add step
        </Button>
      </div>

      {steps.length === 0 ? (
        <p className="rounded-md border border-dashed border-border px-3 py-4 text-center text-xs text-muted-foreground">
          No steps yet. Add ordered actions responders should take, or name a tool for Halon to run a step with.
        </p>
      ) : (
        <div className="space-y-2">
          {steps.map((step, index) => (
            <div key={step.key} className="flex gap-2 rounded-md border border-border/60 p-2.5">
              <div className="flex flex-col items-center gap-1 pt-1.5">
                <IconGripVertical className="size-4 text-fg-disabled" />
                <div className="flex flex-col">
                  <button
                    type="button"
                    className="text-fg-muted hover:text-foreground disabled:opacity-30"
                    disabled={index === 0}
                    onClick={() => move(index, -1)}
                  >
                    <IconChevronUp className="size-3.5" />
                  </button>
                  <button
                    type="button"
                    className="text-fg-muted hover:text-foreground disabled:opacity-30"
                    disabled={index === steps.length - 1}
                    onClick={() => move(index, 1)}
                  >
                    <IconChevronDown className="size-3.5" />
                  </button>
                </div>
              </div>
              <div className="flex-1 space-y-2">
                <Input
                  value={step.title}
                  onChange={(event) => update(index, { title: event.target.value })}
                  placeholder={`Step ${index + 1} title`}
                />
                <Textarea
                  rows={2}
                  value={step.instruction}
                  onChange={(event) => update(index, { instruction: event.target.value })}
                  placeholder="Instruction (optional)"
                />
                <div className="space-y-1">
                  <Label className="text-xs">Tool Halon runs it with</Label>
                  <SearchableSelect
                    value={step.tool}
                    onValueChange={(tool) => chooseTool(index, tool)}
                    options={withSavedTool(toolOptions, step.tool)}
                    placeholder={tools ? "None, a person does this step" : "Loading tools"}
                    searchPlaceholder="Search tools"
                    emptyText="No tool by that name"
                    renderSelected={renderTool}
                  />
                </div>
                {step.tool !== BY_HAND && (
                  <StepToolFields
                    stepKey={step.key}
                    tool={step.tool}
                    tools={tools}
                    args={step.args}
                    errors={stepErrors[step.key] ?? {}}
                    placeholders={placeholders}
                    places={places}
                    onChange={(args) => update(index, { args })}
                  />
                )}
              </div>
              <button
                type="button"
                className="pt-1.5 text-fg-muted hover:text-destructive"
                onClick={() => remove(index)}
              >
                <IconX className="size-4" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// A tool a step was saved with that is not among the choices, such as one this person cannot see, still shows by name.
function withSavedTool(options: SearchableSelectOption[], tool: string): SearchableSelectOption[] {
  if (tool === BY_HAND || options.some((option) => option.value === tool)) {
    return options
  }
  return [ { value: tool, label: tool }, ...options ]
}

function renderTool(option: SearchableSelectOption) {
  return <span className="font-mono text-xs">{option.label}</span>
}

interface StepToolFieldsProps {
  stepKey: string
  tool: string
  tools: RunbookToolChoice[] | null
  args: ArgumentsState
  errors: Record<string, string>
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  onChange: (args: ArgumentsState) => void
}

function StepToolFields({ stepKey, tool, tools, args, errors, placeholders, places, onChange }: StepToolFieldsProps) {
  const choice = tools?.find((candidate) => candidate.name === tool) ?? null

  return (
    <div className="space-y-2 rounded-md border border-border/60 px-3 py-2.5">
      {choice && <p className="text-xs text-muted-foreground">{choice.description}</p>}
      {tools && !choice && (
        <p className="text-xs text-muted-foreground">
          {tool} is not among the tools you can use here, so its arguments are kept as they were saved.
        </p>
      )}
      <RunbookToolFields
        idPrefix={`step-${stepKey}`}
        fields={choice?.fields ?? null}
        state={args}
        errors={errors}
        placeholders={placeholders}
        places={places}
        onChange={onChange}
      />
    </div>
  )
}
