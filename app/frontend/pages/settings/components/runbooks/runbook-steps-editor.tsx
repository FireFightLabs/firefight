import {
  IconChevronDown,
  IconChevronUp,
  IconGripVertical,
  IconPlus,
  IconX,
} from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"

export interface EditableStep {
  key: string
  id?: string
  title: string
  instruction: string
  // The tool Halon runs the step with, by the name Halon calls it, and its arguments as JSON text while being edited.
  tool: string
  argumentsText: string
}

const ARGUMENTS_PLACEHOLDER = '{ "workflow": "release.yml", "inputs": { "bump": "{{bump}}" } }'

export function RunbookStepsEditor({ steps, stepErrors, onChange }: {
  steps: EditableStep[]
  stepErrors: Record<string, string>
  onChange: (steps: EditableStep[]) => void
}) {
  function update(index: number, patch: Partial<EditableStep>) {
    onChange(steps.map((step, position) => (position === index ? { ...step, ...patch } : step)))
  }

  function add() {
    onChange([...steps, { key: crypto.randomUUID(), title: "", instruction: "", tool: "", argumentsText: "" }])
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
                <Input
                  aria-label={`Step ${index + 1} tool`}
                  className="font-mono text-xs"
                  value={step.tool}
                  onChange={(event) => update(index, { tool: event.target.value })}
                  placeholder="Tool Halon runs it with (optional)"
                />
                {step.tool.trim().length > 0 && (
                  <Textarea
                    aria-label={`Step ${index + 1} arguments`}
                    rows={3}
                    className="font-mono text-xs"
                    value={step.argumentsText}
                    onChange={(event) => update(index, { argumentsText: event.target.value })}
                    placeholder={ARGUMENTS_PLACEHOLDER}
                  />
                )}
                {stepErrors[step.key] && <p className="text-xs text-destructive">{stepErrors[step.key]}</p>}
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
