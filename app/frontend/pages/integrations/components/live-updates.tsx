import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconCheck, IconCopy } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { LiveUpdatesOffer } from "@/pages/integrations/components/live-updates-offer"
import {
  liveUpdatesIntegrationPath,
  mapEventsSecretIntegrationPath,
  mapEventsSecretsIntegrationPath,
} from "@/lib/routes"
import { liveUpdatesLine } from "@/pages/map/lib/live-updates"
import type { Integration } from "@/types/serializers"

type LiveUpdatesState = NonNullable<Integration["environments"][number]["liveUpdates"]>

type SetupState = NonNullable<LiveUpdatesState["setup"]>

// What the secret field says, given whether each of the provider's webhooks signs with a secret of its own.
function secretPlaceholder(setup: SetupState): string {
  if (setup.manySecrets) {
    return setup.secretCount > 0 ? `${setup.secretCount} saved. Paste another to add it` : "Paste a signing secret"
  }
  return setup.secretSet ? "Saved. Paste a new one to replace it" : "Paste the signing secret"
}

function secretNote(setup: SetupState): string {
  const accepted = setup.manySecrets
    ? "Each webhook signs with a secret of its own, so add each one. Firefight accepts a change signed with any of them, and a secret is never shown again."
    : "Firefight accepts a change only when it is signed with this secret, and the secret is never shown again."
  return `${accepted} A change is never taken as it is sent. Firefight reads what it names again and updates the map.`
}

// Whether a connection's changes reach the map between sweeps, and for a provider set up by hand, where to send them
// and the secret they are signed with.
export function LiveUpdates({
  integrationId,
  rowId,
  state,
  canManage,
}: {
  integrationId: string
  rowId: string
  state: LiveUpdatesState
  canManage: boolean
}) {
  const [secret, setSecret] = useState("")
  const [copied, setCopied] = useState(false)
  const [confirming, setConfirming] = useState<"on" | "off" | "forget" | null>(null)
  const setup = state.setup
  const secretId = `map-events-secret-${rowId}`

  function changeSecret(event: React.ChangeEvent<HTMLInputElement>) {
    setSecret(event.target.value)
  }

  function clearSecret() {
    setSecret("")
  }

  function saveSecret(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    router.patch(
      mapEventsSecretIntegrationPath(integrationId),
      { environment_row_id: rowId, secret },
      { preserveScroll: true, preserveState: true, onSuccess: clearSecret },
    )
  }

  function askTurnOn() {
    setConfirming("on")
  }

  function askTurnOff() {
    setConfirming("off")
  }

  function stopConfirming() {
    setConfirming(null)
  }

  function askForget() {
    setConfirming("forget")
  }

  function confirmForget() {
    router.delete(mapEventsSecretsIntegrationPath(integrationId), {
      data: { environment_row_id: rowId },
      preserveScroll: true,
      preserveState: true,
      onFinish: stopConfirming,
    })
  }

  function confirmTurn() {
    router.patch(
      liveUpdatesIntegrationPath(integrationId),
      { environment_row_id: rowId, on: confirming === "on" },
      { preserveScroll: true, preserveState: true, onFinish: stopConfirming },
    )
  }

  function markCopied() {
    setCopied(true)
  }

  function copyAddress() {
    if (setup?.address) {
      void navigator.clipboard.writeText(setup.address).then(markCopied)
    }
  }

  return (
    <div className="flex flex-col gap-1.5 px-3 pb-2.5">
      <p className="text-sm">
        <span className={state.on ? "font-medium" : "font-medium text-muted-foreground"}>{liveUpdatesLine(state)}</span>
      </p>
      {state.reason && <p className="text-muted-foreground text-xs">{state.reason}</p>}
      {canManage && (state.turnOn || state.turnOff) && (
        <div className="pt-1">
          {state.turnOn && (
            <Button type="button" size="sm" variant="outline" className="h-8" onClick={askTurnOn}>
              Turn on
            </Button>
          )}
          {state.turnOff && (
            <Button type="button" size="sm" variant="outline" className="h-8" onClick={askTurnOff}>
              Turn off
            </Button>
          )}
        </div>
      )}
      <ConfirmDeleteDialog
        open={confirming === "on"}
        title="Turn on live updates?"
        description={state.turnOn ?? ""}
        confirmLabel="Turn on"
        confirmVariant="default"
        onConfirm={confirmTurn}
        onCancel={stopConfirming}
      />
      <ConfirmDeleteDialog
        open={confirming === "off"}
        title="Turn off live updates?"
        description={state.turnOff ?? ""}
        confirmLabel="Turn off"
        onConfirm={confirmTurn}
        onCancel={stopConfirming}
      />
      {state.offer && canManage && <LiveUpdatesOffer integrationId={integrationId} rowId={rowId} offer={state.offer} />}
      {setup && canManage && (
        <div className="flex flex-col gap-2 pt-1">
          {setup.address ? (
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="h-8 max-w-full justify-start gap-1.5 font-mono text-xs"
              onClick={copyAddress}
            >
              {copied ? <IconCheck className="size-3.5 shrink-0" /> : <IconCopy className="size-3.5 shrink-0" />}
              <span className="truncate">{setup.address}</span>
            </Button>
          ) : (
            <p className="text-muted-foreground text-xs">
              Firefight&apos;s own address is not set, so there is nowhere to send changes yet.
            </p>
          )}
          {setup.steps.length > 0 && (
            <ol className="text-muted-foreground list-decimal space-y-1 pl-5 text-xs">
              {setup.steps.map((step) => (
                <li key={step}>{step}</li>
              ))}
            </ol>
          )}
          <form className="flex flex-wrap items-end gap-2" onSubmit={saveSecret}>
            <div className="flex flex-col gap-1">
              <Label htmlFor={secretId} className="text-xs">
                Signing secret
              </Label>
              <Input
                id={secretId}
                type="password"
                autoComplete="off"
                className="h-8 w-64"
                placeholder={secretPlaceholder(setup)}
                value={secret}
                onChange={changeSecret}
              />
            </div>
            <Button type="submit" size="sm" variant="outline" disabled={secret.trim() === ""}>
              {setup.manySecrets ? "Add secret" : "Save secret"}
            </Button>
            {setup.manySecrets &&
              (setup.forgetSecretsBlocked ? (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <span className="w-fit">
                      <Button type="button" size="sm" variant="outline" disabled>
                        Forget secrets
                      </Button>
                    </span>
                  </TooltipTrigger>
                  <TooltipContent>{setup.forgetSecretsBlocked}</TooltipContent>
                </Tooltip>
              ) : (
                <Button type="button" size="sm" variant="outline" onClick={askForget}>
                  Forget secrets
                </Button>
              ))}
          </form>
          <ConfirmDeleteDialog
            open={confirming === "forget"}
            title="Forget signing secrets?"
            description={setup.forgetSecrets ?? ""}
            confirmLabel="Forget secrets"
            onConfirm={confirmForget}
            onCancel={stopConfirming}
          />
          <p className="text-muted-foreground text-xs">
            {secretNote(setup)}
          </p>
        </div>
      )}
    </div>
  )
}
