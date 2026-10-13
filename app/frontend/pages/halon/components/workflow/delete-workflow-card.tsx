import { router } from "@inertiajs/react"
import { useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { workflowPath } from "@/lib/routes"
import type { WorkflowDetail } from "@/types/serializers"

// Deleting a workflow that never ran, with its draft, its versions and its own identity. One that ran is switched off
// instead, which the button says when it cannot be pressed.
export function DeleteWorkflowCard({ workflow }: { workflow: WorkflowDetail }) {
  const [ confirming, setConfirming ] = useState(false)

  function open() {
    setConfirming(true)
  }

  function close() {
    setConfirming(false)
  }

  function confirmDelete() {
    router.delete(workflowPath(workflow.id), { onFinish: close })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Delete</CardTitle>
        <CardDescription className="mt-1">A workflow that never ran can be deleted. One that ran is switched off instead, so its runs stay readable.</CardDescription>
      </CardHeader>
      <CardContent>
        <Blocked reason={workflow.deletionBlockedReason ?? undefined} side="top">
          <Button type="button" variant="destructive" size="sm" disabled={Boolean(workflow.deletionBlockedReason)} onClick={open}>Delete</Button>
        </Blocked>
      </CardContent>
      <ConfirmDeleteDialog
        open={confirming}
        title={`Delete ${workflow.name}?`}
        description={`${workflow.name} has never run, so no run is lost. Its draft, its versions and its own identity go with it.`}
        onConfirm={confirmDelete}
        onCancel={close}
      />
    </Card>
  )
}
