import { type ChangeEvent, useState } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { ToolFields } from "@/components/tool-fields/tool-fields"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { WORKFLOW_CALL_TOOL } from "@/lib/generated/constants"
import { argumentsState, emptyArguments, fieldErrors, isObject, REFERENCE, type ArgumentsState, type JsonObject } from "@/lib/tool-fields"
import { useCanvasChoices } from "@/pages/halon/hooks/use-canvas-choices"
import type { WorkflowToolChoice } from "@/types/serializers"

// How a person puts a change back, which a step that changes something says before it is published.
const UNDO = "undo"

interface ToolStepEditorProps {
  idPrefix: string
  config: JsonObject
  // Undefined while the tools load.
  tools: WorkflowToolChoice[] | undefined
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

// A Call a tool step: the tool it calls and its arguments, with the form a runbook step's tool uses. Each argument
// takes a value from an earlier step where a fixed one would go.
export function ToolStepEditor({ idPrefix, config, tools, references, disabled, onChange }: ToolStepEditorProps) {
  const [ tool, setTool ] = useState(() => String(config[WORKFLOW_CALL_TOOL.TOOL] ?? ""))
  const [ args, setArgs ] = useState<ArgumentsState>(() => {
    const saved = config[WORKFLOW_CALL_TOOL.ARGUMENTS]
    return argumentsState(isObject(saved) ? saved : null)
  })
  const [ undo, setUndo ] = useState(() => String(config[UNDO] ?? ""))
  const { places } = useCanvasChoices()
  const choice = tools?.find((each) => each.name === tool) ?? null
  const changes = choice !== null && !choice.readOnly
  const options = [
    ...(tool && tools && !choice ? [ { value: tool, label: tool } ] : []),
    ...(tools ?? []).map((each) => ({ value: each.name, label: each.name, group: each.group })),
  ]

  function errorOf(nextTool: string, nextArgs: ArgumentsState, nextUndo: string): string | null {
    if (!nextTool) {
      return "Choose the tool it calls."
    }
    const found = tools?.find((each) => each.name === nextTool)
    if (found && Object.keys(fieldErrors(found.fields, nextArgs, REFERENCE)).length > 0) {
      return "Fill in what the tool needs."
    }
    return found && !found.readOnly && nextUndo.trim().length === 0 ? "Say how a person puts this change back." : null
  }

  function send(nextTool: string, nextArgs: ArgumentsState, nextUndo: string = undo) {
    const next: JsonObject = { ...config, [WORKFLOW_CALL_TOOL.TOOL]: nextTool, [WORKFLOW_CALL_TOOL.ARGUMENTS]: nextArgs.values }
    if (nextUndo.trim()) {
      next[UNDO] = nextUndo
    } else {
      delete next[UNDO]
    }
    onChange(next, errorOf(nextTool, nextArgs, nextUndo))
  }

  function undoTyped(event: ChangeEvent<HTMLTextAreaElement>) {
    setUndo(event.target.value)
    send(tool, args, event.target.value)
  }

  function chooseTool(value: string | null) {
    const next = value ?? ""
    if (next === tool) {
      return
    }
    setTool(next)
    setArgs(emptyArguments())
    send(next, emptyArguments())
  }

  function argsChanged(next: ArgumentsState) {
    setArgs(next)
    send(tool, next)
  }

  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-tool`} className="text-xs">Tool it calls</Label>
        <SearchableSelect id={`${idPrefix}-tool`} value={tool || null} onValueChange={chooseTool} options={options} placeholder={tools ? "Choose a tool" : "Loading tools"}
                          searchPlaceholder="Search tools" emptyText="No tool by that name" disabled={disabled} />
        {choice && <p className="text-xs text-fg-muted">{choice.description}</p>}
        {tools && tool && !choice && <p className="text-xs text-fg-muted">{tool} is not among the tools here, so its arguments are kept as they were saved.</p>}
      </div>
      {tool && (
        <ToolFields
          idPrefix={`${idPrefix}-args`}
          fields={choice?.fields ?? null}
          state={args}
          errors={choice ? fieldErrors(choice.fields, args, REFERENCE) : {}}
          placeholders={references}
          places={places}
          references={references}
          placeholderPattern={REFERENCE}
          disabled={disabled}
          onChange={argsChanged}
        />
      )}
      {changes && (
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-undo`} className="text-xs">How to undo it<span className="text-destructive"> *</span></Label>
          <Textarea id={`${idPrefix}-undo`} value={undo} onChange={undoTyped} disabled={disabled} rows={2} placeholder="Scale it back to 3 replicas." />
          <p className="text-xs text-muted-foreground">It changes something, so say how a person puts it back. A step that reads how it went must run after it.</p>
        </div>
      )}
    </div>
  )
}
