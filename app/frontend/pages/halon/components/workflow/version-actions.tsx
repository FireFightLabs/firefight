import { router } from "@inertiajs/react"
import { IconArrowUp } from "@tabler/icons-react"
import { useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { WORKFLOW_VERSION_STATUS } from "@/lib/generated/constants"
import { askPublishWorkflowPath, publishWorkflowPath, workflowVersionDiscardPath, workflowVersionRestorePath } from "@/lib/routes"
import { PublishDialog } from "@/pages/halon/components/workflow/publish-dialog"
import type { PublishRequestStanding } from "@/pages/halon/components/workflows/types"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"
import { CANVAS_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import type { WorkflowDetail, WorkflowDocument } from "@/types/serializers"

interface VersionActionsProps {
  workflow: WorkflowDetail
  document: WorkflowDocument
  myPublishRequest: PublishRequestStanding
  onLeaveVersion: () => void
}

// What can be done with the version shown: publish the draft or throw it away, ask an admin to publish it for someone
// who may not, or restore an older version as a new draft.
export function VersionActions({ workflow, document, myPublishRequest, onLeaveVersion }: VersionActionsProps) {
  const access = useWorkflowAccess()
  const [ publishing, setPublishing ] = useState(false)
  const [ discarding, setDiscarding ] = useState(false)
  const draft = document.saved && document.status === WORKFLOW_VERSION_STATUS.DRAFT
  const older = document.saved && !draft && document.status !== WORKFLOW_VERSION_STATUS.LIVE
  const askReason = myPublishRequest.waiting ? "You asked the admins, who are told by direct message." : myPublishRequest.askBlockedReason ?? undefined

  function openPublish() {
    setPublishing(true)
  }

  function publish() {
    setPublishing(false)
    router.post(publishWorkflowPath(workflow.id), { revision: document.revision }, CANVAS_VISIT)
  }

  function askDiscard() {
    setDiscarding(true)
  }

  function cancelDiscard() {
    setDiscarding(false)
  }

  function discard() {
    setDiscarding(false)
    if (document.id) {
      router.post(workflowVersionDiscardPath(workflow.id, document.id), {}, CANVAS_VISIT)
    }
  }

  function askAdmin() {
    router.post(askPublishWorkflowPath(workflow.id), {}, CANVAS_VISIT)
  }

  function restore() {
    if (document.id) {
      router.post(workflowVersionRestorePath(workflow.id, document.id), {}, { ...CANVAS_VISIT, preserveUrl: false, onSuccess: onLeaveVersion })
    }
  }

  if (older) {
    return (
      <div className="flex items-center gap-2">
        <Button type="button" variant="outline" size="sm" onClick={onLeaveVersion}>Back to the current version</Button>
        {access.build && (
          <Blocked reason={document.restoreBlockedReason ?? undefined} side="bottom">
            <Button type="button" size="sm" disabled={document.restoreBlockedReason != null} onClick={restore}>Restore as a draft</Button>
          </Blocked>
        )}
      </div>
    )
  }

  if (!draft) {
    return access.manage ? (
      <Blocked reason={document.publishBlockedReason ?? undefined} side="bottom">
        <Button type="button" size="sm" disabled>Publish</Button>
      </Blocked>
    ) : null
  }

  return (
    <div className="flex items-center gap-2">
      {access.build && <Button type="button" variant="outline" size="sm" onClick={askDiscard}>Discard draft</Button>}
      {access.manage ? (
        <Button type="button" size="sm" onClick={openPublish}>Publish v{document.number}</Button>
      ) : access.build ? (
        <Blocked reason={askReason} side="bottom">
          <Button type="button" size="sm" disabled={askReason !== undefined} onClick={askAdmin}>
            <IconArrowUp className="size-4" />
            {myPublishRequest.waiting ? "Asked an admin to publish" : "Ask an admin to publish"}
          </Button>
        </Blocked>
      ) : null}
      <PublishDialog open={publishing} workflow={workflow} document={document} onPublish={publish} onOpenChange={setPublishing} />
      <ConfirmDeleteDialog
        open={discarding}
        title={`Discard the draft of ${workflow.name}?`}
        description={workflow.liveNumber ? `Every change in version ${document.number} is lost, and version ${workflow.liveNumber} stays live.` : `Every change in version ${document.number} is lost.`}
        confirmLabel="Discard draft"
        onConfirm={discard}
        onCancel={cancelDiscard}
      />
    </div>
  )
}
