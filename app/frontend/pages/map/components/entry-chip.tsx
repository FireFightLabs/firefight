import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconX } from "@tabler/icons-react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { resourceMapResourceEntryPath } from "@/lib/routes"
import { MAP_VISIT } from "@/pages/map/lib/visit"
import type { ResourceMapEntry } from "@/types/serializers"

export function EntryChip({ resourceId, entry, canCurate }: { resourceId: string; entry: ResourceMapEntry; canCurate: boolean }) {
  const [ asking, setAsking ] = useState(false)

  function ask() {
    setAsking(true)
  }

  function cancel() {
    setAsking(false)
  }

  function unlink() {
    router.delete(resourceMapResourceEntryPath(resourceId, entry.id), { ...MAP_VISIT, onFinish: cancel })
  }

  return (
    <span className="flex items-center gap-1.5 rounded-md border border-border bg-background/60 py-1 pr-1 pl-2.5 text-sm">
      <span>{entry.name}</span>
      <span className="text-xs text-muted-foreground">{entry.typeName}</span>
      {canCurate && (
        <button type="button" onClick={ask} aria-label={`Unlink ${entry.name}`} className="rounded p-0.5 text-muted-foreground hover:bg-muted hover:text-foreground">
          <IconX className="size-3.5" />
        </button>
      )}
      <ConfirmDeleteDialog
        open={asking}
        title={`Unlink ${entry.name}?`}
        description={`Its incidents stop showing on this resource, and Halon no longer reads this resource as where ${entry.name} runs.`}
        confirmLabel="Unlink"
        onConfirm={unlink}
        onCancel={cancel}
      />
    </span>
  )
}
