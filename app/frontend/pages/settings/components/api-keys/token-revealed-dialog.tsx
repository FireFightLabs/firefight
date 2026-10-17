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
import { whenClosed } from "@/lib/handlers"

const API_KEY_TITLE = "API key created"
const API_KEY_DESCRIPTION = "Copy this token now. For security reasons it cannot be shown again, and there's no way to recover it later."
const API_KEY_WARNING = "If you lose this token, you'll need to revoke this key and create a new one. Store it somewhere safe (a password manager or your secrets store)."

// Shows a credential once. A caller that is not an API key, such as a webhook's signing secret, names it in its own words.
export function TokenRevealedDialog({
  token,
  onDismiss,
  title = API_KEY_TITLE,
  description = API_KEY_DESCRIPTION,
  warning = API_KEY_WARNING,
}: {
  token: string | null
  onDismiss: () => void
  title?: string
  description?: string
  warning?: string
}) {
  const [copied, setCopied] = useState(false)

  const handleCopy = () => {
    if (!token) {
      return
    }
    navigator.clipboard.writeText(token)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  // Cannot be closed by clicking outside or Escape. The token disappears for
  // good, so the user has to confirm they copied it.
  return (
    <Dialog
      open={token !== null}
      onOpenChange={whenClosed(onDismiss)}
    >
      <DialogContent
        className="max-w-lg"
        onPointerDownOutside={(event) => event.preventDefault()}
        onEscapeKeyDown={(event) => event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <IconKey className="size-5 text-brand" />
            {title}
          </DialogTitle>
          <DialogDescription>{description}</DialogDescription>
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

          <div className="edge-bar flex items-start gap-2 rounded-md bg-warning-tint px-3 py-2 [--edge-bar:var(--warning)] text-xs text-fg-primary [&>svg]:text-warning">
            <IconAlertTriangle className="size-4 shrink-0 mt-0.5" />
            <p>{warning}</p>
          </div>
        </div>

        <DialogFooter>
          <Button onClick={onDismiss}>I've copied it</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
