import { useState } from "react"
import { router } from "@inertiajs/react"

import type { IncidentStatusSettings } from "@/types/serializers"
import type { LifecycleStageWithStatuses } from "@/pages/settings/lib/types"
import { incidentStatusesPath, incidentStatusPath } from "@/lib/routes"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { OptionDialog } from "@/pages/settings/components/options/option-dialog"
import { StageStatusesCard } from "@/pages/settings/components/statuses/stage-statuses-card"

export function StatusesTab({ lifecycleStages }: { lifecycleStages: LifecycleStageWithStatuses[] }) {
  const [editing, setEditing] = useState<IncidentStatusSettings | null>(null)
  const [creatingIn, setCreatingIn] = useState<LifecycleStageWithStatuses | null>(null)
  const [deleting, setDeleting] = useState<IncidentStatusSettings | null>(null)

  return (
    <div className="flex flex-col gap-6">
      {lifecycleStages.map((stage) => (
        <StageStatusesCard
          key={stage.key}
          stage={stage}
          onCreate={setCreatingIn}
          onEdit={setEditing}
          onDelete={setDeleting}
        />
      ))}

      {creatingIn && (
        <OptionDialog
          open
          onOpenChange={(open) => { if (!open) setCreatingIn(null) }}
          title={`Add ${creatingIn.name} Status`}
          description={`Create a new status in the ${creatingIn.name} stage.`}
          submitLabel="Create Status"
          namePlaceholder="e.g. Mitigating"
          descriptionPlaceholder="When is an incident in this status?"
          initial={{ name: "", description: "", color: "#6B7280" }}
          action={incidentStatusesPath()}
          method="post"
          extraParams={{ lifecycle_stage_key: creatingIn.key }}
        />
      )}

      {editing && (
        <OptionDialog
          open
          onOpenChange={(open) => { if (!open) setEditing(null) }}
          title="Edit Status"
          description="Update the name, description, or color for this status."
          submitLabel="Save Changes"
          initial={{
            id: editing.id,
            name: editing.name,
            description: editing.description ?? "",
            color: editing.color,
          }}
          action={incidentStatusPath(editing.id)}
          method="patch"
        />
      )}

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this status"}?`}
        description="No incidents use this status, so nothing loses its history. It disappears from the status picker straight away."
        onConfirm={() => {
          if (!deleting) return
          router.delete(incidentStatusPath(deleting.id), { onFinish: () => setDeleting(null) })
        }}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}
