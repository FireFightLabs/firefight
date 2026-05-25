import { useState } from "react"
import { IconAlertTriangle, IconClipboard, IconKey } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"

export function TokenRevealedDialog({
  token,
  onDismiss,
}: {
  token: string | null
  onDismiss: () => void
}) {
  const [copied, setCopied] = useState(false)

  const handleCopy = () => {
    if (!token) return
    navigator.clipboard.writeText(token)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  // Modal cannot be closed by clicking outside or pressing Escape — the user
  // has to acknowledge they've copied the token before it disappears for good.
  return (
    <Dialog
      open={token !== null}
      onOpenChange={(open) => { if (!open) onDismiss() }}
    >
      <DialogContent
        className="max-w-lg"
        onPointerDownOutside={(e) => e.preventDefault()}
        onEscapeKeyDown={(e) => e.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <IconKey className="size-5 text-primary" />
            API key created
          </DialogTitle>
          <DialogDescription>
            Copy this token now. For security reasons it cannot be shown again,
            and there's no way to recover it later.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-3 py-2">
          <div className="flex items-center gap-2">
            <code className="flex-1 rounded-md bg-muted px-3 py-2 font-mono text-sm break-all">
              {token ?? ""}
            </code>
            <Button variant="outline" size="sm" onClick={handleCopy}>
              <IconClipboard className="size-4" />
              {copied ? "Copied!" : "Copy"}
            </Button>
          </div>

          <div className="flex items-start gap-2 rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-700 dark:text-amber-400">
            <IconAlertTriangle className="size-4 shrink-0 mt-0.5" />
            <p>
              If you lose this token, you'll need to revoke this key and create a new one.
              Store it somewhere safe (a password manager or your secrets store).
            </p>
          </div>
        </div>

        <DialogFooter>
          <Button onClick={onDismiss}>I've copied it</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
