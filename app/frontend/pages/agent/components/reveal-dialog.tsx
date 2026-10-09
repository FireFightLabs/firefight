import { Dialog, DialogContent } from "@/components/ui/dialog"
import { whenClosed } from "@/lib/handlers"
import { RevealedValue } from "@/pages/agent/components/revealed-value"
import type { SecretDialogProps } from "@/pages/agent/types"

export function RevealDialog({ conversationId, entry, open, onClose }: SecretDialogProps) {
  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="max-w-lg">
        <RevealedValue conversationId={conversationId} entry={entry} onClose={onClose} />
      </DialogContent>
    </Dialog>
  )
}
