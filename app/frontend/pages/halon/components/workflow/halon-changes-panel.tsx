import { router } from "@inertiajs/react"
import { IconArrowBackUp, IconSparkles } from "@tabler/icons-react"
import { useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { shortAgo } from "@/lib/time"
import { workflowUndoPath } from "@/lib/routes"
import { CANVAS_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import type { WorkflowHalonChange } from "@/types/serializers"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"

// Changes by Halon: what Halon changed in this version and the one it came from, each with why and who accepted it, and
// Undo, which takes it back out as a person's change and keeps what people did around it. The steps it changed are
// ringed in violet on the canvas while this is open.
export function HalonChangesPanel({ workflowId, changes }: { workflowId: string; changes: WorkflowHalonChange[] }) {
  const canEdit = useWorkflowAccess().build
  const [ undoingAll, setUndoingAll ] = useState(false)
  const undoable = changes.filter((change) => !change.undoBlockedReason)

  function undo(change: WorkflowHalonChange) {
    return () => router.post(workflowUndoPath(workflowId), change.changeSetId ? { change_set_id: change.changeSetId } : { edit_id: change.editId }, CANVAS_VISIT)
  }

  function askUndoAll() {
    setUndoingAll(true)
  }

  function cancelUndoAll() {
    setUndoingAll(false)
  }

  function undoAll() {
    setUndoingAll(false)
    router.post(workflowUndoPath(workflowId), {}, CANVAS_VISIT)
  }

  return (
    <section aria-label="Changes by Halon" className="w-80 max-w-[calc(100vw-2rem)] rounded-md border border-halon-border bg-background/95 shadow-popover">
      <header className="flex items-center gap-2 border-b border-border px-3 py-2">
        <IconSparkles className="size-3.5 text-halon" />
        <h3 className="flex-1 text-[12.5px] font-medium text-fg-primary">Changes by Halon</h3>
        {canEdit && undoable.length > 1 && (
          <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-[11.5px]" onClick={askUndoAll}>Undo all</Button>
        )}
      </header>
      {changes.length === 0 ? (
        <p className="px-3 py-4 text-xs text-fg-muted">Halon has not changed this version.</p>
      ) : (
        <ol className="max-h-80 divide-y divide-border overflow-y-auto">
          {changes.map((change) => (
            <li key={change.key} className="space-y-1.5 px-3 py-2.5">
              {change.sentences.map((sentence) => <p key={sentence} className="text-xs text-fg-primary">{sentence}</p>)}
              {change.reason && <p className="text-xs leading-snug text-fg-secondary">{change.reason}</p>}
              <div className="flex items-center gap-2">
                <p className="flex-1 text-[11px] text-fg-muted">
                  Version {change.versionNumber} · {shortAgo(change.createdAt)}
                  {change.acceptedByName && ` · accepted by ${change.acceptedByName}`}
                </p>
                {canEdit && (
                  <Blocked reason={change.undoBlockedReason ?? undefined} side="left">
                    <Button type="button" variant="outline" size="sm" className="h-6 gap-1 px-2 text-[11.5px]" disabled={change.undoBlockedReason != null} onClick={undo(change)}>
                      <IconArrowBackUp className="size-3.5" />
                      Undo
                    </Button>
                  </Blocked>
                )}
              </div>
            </li>
          ))}
        </ol>
      )}
      <ConfirmDeleteDialog
        open={undoingAll}
        title="Undo all of Halon's changes?"
        description={`Every change of Halon's listed here is taken back out, ${undoable.length} in all. What people changed around them stays.`}
        confirmLabel="Undo all"
        onConfirm={undoAll}
        onCancel={cancelUndoAll}
      />
    </section>
  )
}
