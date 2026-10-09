import { Dialog, DialogContent } from "@/components/ui/dialog"
import { whenClosed } from "@/lib/handlers"
import { EnterValueForm } from "@/pages/agent/components/enter-value-form"
import type { SecretDialogProps } from "@/pages/agent/types"

export function EnterValueDialog({ conversationId, entry, open, onClose }: SecretDialogProps) {
  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="sm:max-w-md">
        <EnterValueForm conversationId={conversationId} entry={entry} onClose={onClose} />
      </DialogContent>
    </Dialog>
  )
}
