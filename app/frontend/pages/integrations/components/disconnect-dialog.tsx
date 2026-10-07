import { useState } from "react"
import { router } from "@inertiajs/react"

import type { Integration } from "@/types/serializers"
import { integrationPath } from "@/lib/routes"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Checkbox } from "@/components/ui/checkbox"
import { Label } from "@/components/ui/label"

type Installation = Integration["installations"][number]

// Ticked by default, unless another connection still uses the installation, in which case it cannot be ticked at all.
function initiallyChosen(installations: Installation[]) {
  return installations
    .filter((installation) => !installation.blockedReason)
    .map((installation) => installation.installationId)
}

export function DisconnectDialog({
  integration,
  open,
  onClose,
}: {
  integration: Integration
  open: boolean
  onClose: () => void
}) {
  const [chosen, setChosen] = useState<string[]>(() => initiallyChosen(integration.installations))

  function choose(installationId: string, checked: boolean) {
    setChosen((current) =>
      checked ? [...current, installationId] : current.filter((each) => each !== installationId),
    )
  }

  function disconnect() {
    router.delete(integrationPath(integration.id), {
      data: { uninstall: chosen },
      onFinish: onClose,
    })
  }

  return (
    <ConfirmDeleteDialog
      open={open}
      title={`Disconnect ${integration.name}?`}
      description="Halon, chats and connected agents can no longer use its tools, and the resource map stops reading it. You can connect it again at any time."
      confirmLabel="Disconnect"
      onConfirm={disconnect}
      onCancel={onClose}
    >
      {integration.installations.length > 0 && (
        <div className="flex flex-col gap-3">
          {integration.installations.map((installation) => {
            const checkboxId = `uninstall-${integration.id}-${installation.installationId}`
            return (
              <div key={installation.installationId} className="flex items-start gap-2.5">
                <Checkbox
                  id={checkboxId}
                  className="mt-0.5"
                  checked={chosen.includes(installation.installationId)}
                  disabled={Boolean(installation.blockedReason)}
                  onCheckedChange={(checked) => choose(installation.installationId, checked === true)}
                />
                <div className="flex flex-col gap-0.5">
                  <Label htmlFor={checkboxId} className="text-sm leading-snug font-normal">
                    {installation.label}
                  </Label>
                  {installation.blockedReason && (
                    <p className="text-muted-foreground text-xs">{installation.blockedReason}</p>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}
    </ConfirmDeleteDialog>
  )
}
