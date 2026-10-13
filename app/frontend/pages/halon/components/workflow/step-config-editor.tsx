import type { SearchableSelectOption } from "@/components/searchable-select"
import { WORKFLOW_STEP_EDITOR } from "@/lib/generated/constants"
import type { JsonObject } from "@/lib/tool-fields"
import { AskHalonEditor } from "@/pages/halon/components/workflow/ask-halon-editor"
import { BranchEditor } from "@/pages/halon/components/workflow/branch-editor"
import { DelayEditor } from "@/pages/halon/components/workflow/delay-editor"
import { FieldsEditor } from "@/pages/halon/components/workflow/fields-editor"
import { ForEachEditor } from "@/pages/halon/components/workflow/for-each-editor"
import { RunWorkflowEditor } from "@/pages/halon/components/workflow/run-workflow-editor"
import { ToolStepEditor } from "@/pages/halon/components/workflow/tool-step-editor"
import { WatchEditor } from "@/pages/halon/components/workflow/watch-editor"
import type { OtherWorkflow } from "@/pages/halon/lib/workflow/types"
import type { WorkflowStepKind, WorkflowStepNode, WorkflowToolChoice } from "@/types/serializers"

interface StepConfigEditorProps {
  step: WorkflowStepNode
  config: JsonObject
  kind: WorkflowStepKind | null
  tools: WorkflowToolChoice[] | undefined
  workflows: OtherWorkflow[]
  timeZones: string[]
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error?: string | null) => void
}

// A step's settings, drawn the way its kind says: the tool field form over its fields, or an editor of its own for a
// branch's routes, a delay, a for each, the workflow it runs, the tool it calls, what Halon is asked or what is watched.
export function StepConfigEditor({ step, config, kind, tools, workflows, timeZones, references, disabled, onChange }: StepConfigEditorProps) {
  const idPrefix = `step-${step.id}`
  switch (step.editor) {
  case WORKFLOW_STEP_EDITOR.BRANCH:
    return <BranchEditor idPrefix={idPrefix} config={config} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.DELAY:
    return <DelayEditor idPrefix={idPrefix} config={config} timeZones={timeZones} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.FOR_EACH:
    return <ForEachEditor idPrefix={idPrefix} config={config} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.RUN_WORKFLOW:
    return <RunWorkflowEditor idPrefix={idPrefix} config={config} workflows={workflows} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.TOOL:
    return <ToolStepEditor idPrefix={idPrefix} config={config} tools={tools} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.ASK_HALON:
    return <AskHalonEditor idPrefix={idPrefix} config={config} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.WATCH:
    return <WatchEditor idPrefix={idPrefix} config={config} tools={tools} references={references} disabled={disabled} onChange={onChange} />
  default:
    return <FieldsEditor idPrefix={idPrefix} fields={kind?.fields ?? []} values={config} references={references} disabled={disabled} onChange={onChange} />
  }
}
