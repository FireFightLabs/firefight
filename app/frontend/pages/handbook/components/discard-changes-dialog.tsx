import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"

interface DiscardChangesDialogProps {
  open: boolean
  onDiscard: () => void
  onKeepEditing: () => void
}

// Asked before leaving a page with unsaved changes, so nothing written is lost by a stray click.
export function DiscardChangesDialog({ open, onDiscard, onKeepEditing }: DiscardChangesDialogProps) {
  return (
    <ConfirmDeleteDialog
      open={open}
      title="Discard your changes?"
      description="What you wrote on this page is not saved yet. Keep editing to save it, or discard it."
      confirmLabel="Discard changes"
      cancelLabel="Keep editing"
      onConfirm={onDiscard}
      onCancel={onKeepEditing}
    />
  )
}
