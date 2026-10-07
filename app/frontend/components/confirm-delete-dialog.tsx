import type { ReactNode } from "react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"

export function ConfirmDeleteDialog({
  open,
  title,
  description,
  confirmLabel = "Delete",
  confirmVariant = "destructive",
  onConfirm,
  onCancel,
  children,
}: {
  open: boolean
  title: string
  description: string
  confirmLabel?: string
  // A confirmation that adds rather than removes, such as turning something on, is not drawn as destructive.
  confirmVariant?: "destructive" | "default"
  onConfirm: () => void
  onCancel: () => void
  // A choice that goes with the confirmation, such as also removing something elsewhere.
  children?: ReactNode
}) {
  return (
    <Dialog open={open} onOpenChange={(next) => !next && onCancel()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        {children}
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onCancel}>Cancel</Button>
          <Button type="button" variant={confirmVariant} onClick={onConfirm}>{confirmLabel}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
