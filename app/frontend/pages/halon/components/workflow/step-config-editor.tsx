import type { SearchableSelectOption } from "@/components/searchable-select"
import { WORKFLOW_STEP_EDITOR } from "@/lib/generated/constants"
import type { JsonObject } from "@/lib/tool-fields"
import { ApprovalEditor } from "@/pages/halon/components/workflow/approval-editor"
import { AskHalonEditor } from "@/pages/halon/components/workflow/ask-halon-editor"
import { AskPersonEditor } from "@/pages/halon/components/workflow/ask-person-editor"
import { BranchEditor } from "@/pages/halon/components/workflow/branch-editor"
import { BrowserEditor } from "@/pages/halon/components/workflow/browser-editor"
import { DelayEditor } from "@/pages/halon/components/workflow/delay-editor"
import { FieldsEditor } from "@/pages/halon/components/workflow/fields-editor"
import { ForEachEditor } from "@/pages/halon/components/workflow/for-each-editor"
import { RunWorkflowEditor } from "@/pages/halon/components/workflow/run-workflow-editor"
import { SetDataEditor } from "@/pages/halon/components/workflow/set-data-editor"
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

// The tools a Status page update step may call: those of connected status pages that change something.
function statusPageTools(tools: WorkflowToolChoice[] | undefined): WorkflowToolChoice[] | undefined {
  return tools?.filter((tool) => tool.statusPage && !tool.readOnly)
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
  case WORKFLOW_STEP_EDITOR.BROWSER:
    return <BrowserEditor idPrefix={idPrefix} config={config} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.STATUS_PAGE:
    return <ToolStepEditor idPrefix={idPrefix} config={config} tools={statusPageTools(tools)} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.ASK_HALON:
    return <AskHalonEditor idPrefix={idPrefix} config={config} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.SET_DATA:
    return <SetDataEditor config={config} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.ASK_PERSON:
    return <AskPersonEditor idPrefix={idPrefix} kind={kind} config={config} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.APPROVAL:
    return <ApprovalEditor idPrefix={idPrefix} kind={kind} config={config} references={references} disabled={disabled} onChange={onChange} />
  case WORKFLOW_STEP_EDITOR.WATCH:
    return <WatchEditor idPrefix={idPrefix} config={config} tools={tools} references={references} disabled={disabled} onChange={onChange} />
  default:
    return <FieldsEditor idPrefix={idPrefix} fields={kind?.fields ?? []} values={config} references={references} disabled={disabled} onChange={onChange} />
  }
}
