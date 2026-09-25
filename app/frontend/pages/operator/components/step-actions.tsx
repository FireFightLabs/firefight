import { IconPlayerTrackNext, IconRefresh } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { runAgainOperatorWorkflowStepPath, skipOperatorWorkflowStepPath } from "@/lib/routes"
import { useAction } from "@/pages/operator/lib/use-action"

// Run again and Skip buttons for a failed step. Skip asks for confirmation first.
export function StepActions({ stepId, stepName }: { stepId: string; stepName: string }) {
  const [confirmingSkip, setConfirmingSkip] = useState(false)
  const { busy, post } = useAction()

  function runAgain() {
    post(runAgainOperatorWorkflowStepPath(stepId))
  }

  function askToSkip() {
    setConfirmingSkip(true)
  }

  function stopAsking() {
    setConfirmingSkip(false)
  }

  function skip() {
    setConfirmingSkip(false)
    post(skipOperatorWorkflowStepPath(stepId))
  }

  return (
    <div className="flex gap-2">
      <Button type="button" size="sm" variant="outline" onClick={runAgain} disabled={busy}>
        <IconRefresh className="size-3.5" />
        Run again
      </Button>
      <Button type="button" size="sm" variant="ghost" onClick={askToSkip} disabled={busy}>
        <IconPlayerTrackNext className="size-3.5" />
        Skip
      </Button>
      <ConfirmDeleteDialog
        open={confirmingSkip}
        title={`Skip ${stepName}?`}
        description="The workflow carries on as if this step had succeeded, and what it would have done does not happen. Steps that depend on it run next."
        confirmLabel="Skip step"
        onConfirm={skip}
        onCancel={stopAsking}
      />
    </div>
  )
}
