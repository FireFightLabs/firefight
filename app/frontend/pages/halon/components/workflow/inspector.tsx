import { IconPointer } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { WORKFLOW_EDIT_OPERATIONS } from "@/lib/generated/constants"
import { StepSettings } from "@/pages/halon/components/workflow/step-settings"
import { TriggerSettings } from "@/pages/halon/components/workflow/trigger-settings"
import { revisionOf, type SendEdit } from "@/pages/halon/hooks/use-workflow-edits"
import { canvasSteps } from "@/pages/halon/lib/workflow/canvas-graph"
import type { OtherWorkflow, Selection } from "@/pages/halon/lib/workflow/types"
import type { WorkflowDocument, WorkflowStepKind, WorkflowSuggestion, WorkflowToolChoice, WorkflowTriggerKind } from "@/types/serializers"

interface InspectorProps {
  workflowId: string
  document: WorkflowDocument
  suggestions: WorkflowSuggestion[]
  selection: Selection
  stepKinds: WorkflowStepKind[]
  triggerKinds: WorkflowTriggerKind[]
  tools: WorkflowToolChoice[] | undefined
  workflows: OtherWorkflow[]
  timeZones: string[]
  editable: boolean
  send: SendEdit
  onSelect: (selection: Selection) => void
  onTry: (stepId: string) => void
}

// The settings beside the canvas: the trigger's or the selected step's, or a line saying how to pick one. Removing a
// step asks first, naming what goes with it.
export function Inspector({ workflowId, document, suggestions, selection, stepKinds, triggerKinds, tools, workflows, timeZones, editable, send, onSelect, onTry }: InspectorProps) {
  const [ removing, setRemoving ] = useState(false)
  const revision = revisionOf(document)
  const triggerKind = triggerKinds.find((kind) => kind.key === document.trigger.kind) ?? null
  const item = selection?.kind === "step" ? canvasSteps(document.steps, suggestions).find((each) => each.step.id === selection.id) ?? null : null
  const connections = item ? document.edges.filter((edge) => edge.from === item.step.id || edge.to === item.step.id).length : 0
  const inside = item ? document.steps.filter((step) => step.within === item.step.id).length : 0

  function askRemove() {
    setRemoving(true)
  }

  function cancelRemove() {
    setRemoving(false)
  }

  function remove() {
    setRemoving(false)
    if (item) {
      send(WORKFLOW_EDIT_OPERATIONS.REMOVE_STEP, { step_id: item.step.id }, { onSuccess: () => onSelect(null) })
    }
  }

  if (selection?.kind === "trigger") {
    return (
      <TriggerSettings
        trigger={document.trigger}
        kind={triggerKind}
        pending={suggestions.filter((suggestion) => suggestion.operation === WORKFLOW_EDIT_OPERATIONS.CHANGE_TRIGGER)}
        revision={revision}
        timeZones={timeZones}
        editable={editable}
        send={send}
      />
    )
  }

  if (!item) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2 px-6 text-center">
        <IconPointer className="size-5 text-fg-disabled" />
        <p className="text-[12.5px] text-fg-muted">Select a step to set it up, or the trigger to change what starts a run.</p>
      </div>
    )
  }

  const goesWith = [
    connections > 0 ? `its ${connections === 1 ? "connection" : `${connections} connections`}` : null,
    inside > 0 ? `the ${inside === 1 ? "step" : `${inside} steps`} inside it` : null,
  ].filter((part) => part !== null).join(" and ")

  return (
    <>
      <StepSettings
        key={item.step.id}
        workflowId={workflowId}
        item={item}
        document={document}
        revision={revision}
        stepKinds={stepKinds}
        triggerOutputs={triggerKind?.outputs ?? []}
        tools={tools}
        workflows={workflows}
        timeZones={timeZones}
        editable={editable}
        send={send}
        onRemove={askRemove}
        onTry={onTry}
      />
      <ConfirmDeleteDialog
        open={removing}
        title={`Remove ${item.step.title}?`}
        description={goesWith ? `It leaves the draft with ${goesWith}. Later steps that read it need another value.` : "It leaves the draft. Later steps that read it need another value."}
        confirmLabel="Remove step"
        onConfirm={remove}
        onCancel={cancelRemove}
      />
    </>
  )
}
