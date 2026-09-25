import { router } from "@inertiajs/react"
import { IconPlayerTrackNext, IconRefresh } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { runAgainOperatorWorkflowStepPath, skipOperatorWorkflowStepPath } from "@/lib/routes"

const IN_PLACE = { preserveScroll: true }

// A failed step can run again now, or be skipped so the rest of its workflow carries on. Skipping asks first.
export function StepActions({ stepId, stepName }: { stepId: string; stepName: string }) {
  const [confirmingSkip, setConfirmingSkip] = useState(false)

  function runAgain() {
    router.post(runAgainOperatorWorkflowStepPath(stepId), {}, IN_PLACE)
  }

  function askToSkip() {
    setConfirmingSkip(true)
  }

  function stopAsking() {
    setConfirmingSkip(false)
  }

  function skip() {
    setConfirmingSkip(false)
    router.post(skipOperatorWorkflowStepPath(stepId), {}, IN_PLACE)
  }

  return (
    <div className="flex gap-2">
      <Button type="button" size="sm" variant="outline" onClick={runAgain}>
        <IconRefresh className="size-3.5" />
        Run again
      </Button>
      <Button type="button" size="sm" variant="ghost" onClick={askToSkip}>
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
