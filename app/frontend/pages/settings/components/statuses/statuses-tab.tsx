import { useState } from "react"
import { router } from "@inertiajs/react"

import type { IncidentStatusSettings } from "@/types/serializers"
import type { LifecycleStageWithStatuses } from "@/pages/settings/lib/types"
import { incidentStatusesPath, incidentStatusPath } from "@/lib/routes"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { OptionDialog, type OptionDialogState } from "@/pages/settings/components/option-dialog"
import { StageStatusesCard } from "@/pages/settings/components/statuses/stage-statuses-card"

export function StatusesTab({ lifecycleStages }: { lifecycleStages: LifecycleStageWithStatuses[] }) {
  const [dialog, setDialog] = useState<OptionDialogState<IncidentStatusSettings>>(null)
  const [creatingIn, setCreatingIn] = useState<LifecycleStageWithStatuses | null>(null)
  const [deleting, setDeleting] = useState<IncidentStatusSettings | null>(null)

  function closeDialog() {
    setDialog(null)
    setCreatingIn(null)
  }

  function startCreating(target: LifecycleStageWithStatuses) {
    setCreatingIn(target)
    setDialog({ mode: "create" })
  }

  return (
    <div className="flex flex-col gap-6">
      {lifecycleStages.map((stage) => (
        <StageStatusesCard
          key={stage.key}
          stage={stage}
          onCreate={startCreating}
          onEdit={(option) => setDialog({ mode: "edit", option })}
          onDelete={setDeleting}
        />
      ))}

      <OptionDialog
        state={dialog}
        onClose={closeDialog}
        noun="Status"
        createTitle={creatingIn ? `Add ${creatingIn.name} Status` : undefined}
        createDescription={creatingIn ? `Create a new status in the ${creatingIn.name} stage.` : undefined}
        createPath={incidentStatusesPath()}
        editPath={incidentStatusPath}
        defaultColor="#6B7280"
        namePlaceholder="e.g. Mitigating"
        descriptionPlaceholder="When is an incident in this status?"
        extraParams={creatingIn ? { lifecycle_stage_key: creatingIn.key } : undefined}
      />

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this status"}?`}
        description="No incidents use this status, so nothing loses its history. It disappears from the status picker straight away."
        onConfirm={() => {
          if (!deleting) {
            return
          }
          router.delete(incidentStatusPath(deleting.id), { onFinish: () => setDeleting(null) })
        }}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}
