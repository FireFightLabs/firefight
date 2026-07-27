import { useState } from "react"
import { router } from "@inertiajs/react"

import type { IncidentStatusSettings } from "@/types/serializers"
import type { LifecycleStageWithStatuses } from "@/pages/settings/lib/types"
import { incidentStatusPath } from "@/lib/routes"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { EditStatusDialog } from "@/pages/settings/components/statuses/edit-status-dialog"
import { StageStatusesCard } from "@/pages/settings/components/statuses/stage-statuses-card"

interface StatusesTabProps {
  lifecycleStages: LifecycleStageWithStatuses[]
}

export function StatusesTab({ lifecycleStages }: StatusesTabProps) {
  const [editingStatus, setEditingStatus] = useState<IncidentStatusSettings | null>(null)
  const [deletingStatus, setDeletingStatus] = useState<IncidentStatusSettings | null>(null)

  function confirmDelete() {
    if (!deletingStatus) return
    router.delete(incidentStatusPath(deletingStatus.id), {
      onFinish: () => setDeletingStatus(null),
    })
  }

  return (
    <div className="flex flex-col gap-6">
      {lifecycleStages.map((stage) => (
        <StageStatusesCard
          key={stage.key}
          stage={stage}
          onEdit={setEditingStatus}
          onDelete={setDeletingStatus}
        />
      ))}

      {editingStatus && (
        <EditStatusDialog
          status={editingStatus}
          open={!!editingStatus}
          onOpenChange={(open) => { if (!open) setEditingStatus(null) }}
        />
      )}

      <ConfirmDeleteDialog
        open={Boolean(deletingStatus)}
        title={`Delete ${deletingStatus?.name ?? "this status"}?`}
        description="No incidents use this status, so nothing loses its history. It disappears from the status picker straight away."
        onConfirm={confirmDelete}
        onCancel={() => setDeletingStatus(null)}
      />
    </div>
  )
}
