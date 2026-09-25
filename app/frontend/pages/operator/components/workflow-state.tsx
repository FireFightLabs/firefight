import type { OperatorWorkflowRow } from "@/types/serializers"
import { TONE_CLASSES, WORKFLOW_STATE_TONES } from "@/pages/operator/lib/tone"

export function WorkflowState({ state }: { state: OperatorWorkflowRow["state"] }) {
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium capitalize ${TONE_CLASSES[WORKFLOW_STATE_TONES[state]]}`}>
      <span className="size-1.5 rounded-full bg-current" />
      {state}
    </span>
  )
}
