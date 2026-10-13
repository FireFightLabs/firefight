import { useState } from "react"
import { router } from "@inertiajs/react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { publishWorkflowPath } from "@/lib/routes"
import type { WorkflowDetail } from "@/types/serializers"

function lowerFirst(words: string): string {
  return words.charAt(0).toLowerCase() + words.slice(1)
}

function descriptionOf(workflow: WorkflowDetail, missing: string[]): string {
  const runs = workflow.shownTriggerWords ? `It becomes the live version and runs ${lowerFirst(workflow.shownTriggerWords)}.` : "It becomes the live version."
  if (missing.length === 0) {
    return `${runs} It already holds everything its steps need, so nothing new is granted.`
  }
  return `${runs} Publishing also lets it do the following, granted to the workflow alone in every environment.`
}

// Publishing makes the draft live and grants the workflow's own identity what its steps need, said before it happens.
export function PublishDialog({ workflow, open, onClose }: { workflow: WorkflowDetail; open: boolean; onClose: () => void }) {
  const [processing, setProcessing] = useState(false)
  const missing = workflow.reach.filter((need) => !need.held).map((need) => need.label)

  function finish() {
    setProcessing(false)
    onClose()
  }

  function confirm() {
    if (processing) {
      return
    }
    setProcessing(true)
    router.post(publishWorkflowPath(workflow.id), {}, { preserveScroll: true, onFinish: finish })
  }

  return (
    <ConfirmDeleteDialog
      open={open}
      title={`Publish ${workflow.name}?`}
      description={descriptionOf(workflow, missing)}
      confirmLabel="Publish"
      confirmVariant="default"
      onConfirm={confirm}
      onCancel={onClose}
    >
      {missing.length > 0 && (
        <ul className="list-disc space-y-1 pl-5 text-sm">
          {missing.map((label) => <li key={label}>{label}</li>)}
        </ul>
      )}
    </ConfirmDeleteDialog>
  )
}
