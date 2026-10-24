import { useState, type ChangeEvent, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import { IconCheck, IconCopy } from "@tabler/icons-react"
import { toast } from "sonner"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { postJson } from "@/lib/http"
import {
  mapEventsSecretIntegrationPath,
  mapEventsSecretsIntegrationPath,
} from "@/lib/routes"
import { TokenRevealedDialog } from "@/pages/settings/components/api-keys/token-revealed-dialog"
import type { Integration } from "@/types/serializers"

type SetupState = NonNullable<NonNullable<Integration["environments"][number]["liveUpdates"]>["setup"]>

const COPIED_FOR_MS = 1500

// What the secret field says, given whether each of the provider's webhooks signs with a secret of its own.
function secretPlaceholder(setup: SetupState): string {
  if (setup.manySecrets) {
    return setup.secretCount > 0 ? `${setup.secretCount} saved. Paste another to add it` : "Paste a signing secret"
  }
  return setup.secretSet ? "Saved. Paste a new one to replace it" : "Paste the signing secret"
}

// Firefight's address with a way to copy it, read in full however long it is.
function AddressCopy({ address }: { address: string }) {
  const [copied, setCopied] = useState(false)

  function clearCopied() {
    setCopied(false)
  }

  function markCopied() {
    setCopied(true)
    setTimeout(clearCopied, COPIED_FOR_MS)
  }

  function copyAddress() {
    void navigator.clipboard.writeText(address).then(markCopied)
  }

  return (
    <div className="flex flex-col gap-1">
      <p className="text-xs font-medium">Firefight&apos;s address</p>
      <div className="flex items-start gap-2">
        <p data-map-events-address className="text-muted-foreground min-w-0 flex-1 font-mono text-xs break-all">
          {address}
        </p>
        <Tooltip>
          <TooltipTrigger asChild>
            <Button type="button" variant="outline" size="sm" className="h-7 shrink-0 gap-1.5 px-2 text-xs" onClick={copyAddress}>
              {copied ? <IconCheck className="size-3.5" /> : <IconCopy className="size-3.5" />}
              {copied ? "Copied" : "Copy"}
            </Button>
          </TooltipTrigger>
          <TooltipContent>Copy Firefight&apos;s address</TooltipContent>
        </Tooltip>
      </div>
    </div>
  )
}

const SECRET_TITLE = "Signing secret"
const SECRET_DESCRIPTION = "Copy this secret now and give it to each webhook that sends to Firefight's address. It cannot be shown again."
const SECRET_WARNING = "If you lose it, replace the signing secret here and give each webhook the new one. The old one stops working at once."

type MadeAnswer = { secret?: string; notice?: string; error?: string }

// A secret Firefight makes, for a provider that takes whatever secret its webhook is given. The request that makes it
// answers it once, so it is shown here once and never rides in the page. After that it can only be replaced, which
// asks first since the saved one stops working at once.
function MadeSecret({ integrationId, rowId, setup }: { integrationId: string; rowId: string; setup: SetupState }) {
  const [replacing, setReplacing] = useState(false)
  const [revealed, setRevealed] = useState<string | null>(null)
  const [problem, setProblem] = useState<string | null>(null)

  async function make(replace: boolean) {
    setProblem(null)
    try {
      const { ok, data } = await postJson<MadeAnswer>(mapEventsSecretsIntegrationPath(integrationId), { environment_row_id: rowId, replace })
      if (!ok || !data?.secret) {
        setProblem(data?.error ?? "The secret could not be made. Try again.")
        return
      }
      setRevealed(data.secret)
      toast.success(data.notice)
      router.reload({ only: ["integrations"] })
    } catch {
      setProblem("Firefight could not be reached. Try again.")
    } finally {
      setReplacing(false)
    }
  }

  function makeSecret() {
    void make(false)
  }

  function confirmReplace() {
    void make(true)
  }

  function askReplace() {
    setReplacing(true)
  }

  function stopReplacing() {
    setReplacing(false)
  }

  function closeSecret() {
    setRevealed(null)
  }

  return (
    <div className="flex flex-col gap-1">
      <p className="text-xs font-medium">Signing secret</p>
      <div>
        {setup.secretSet ? (
          <Button type="button" size="sm" variant="outline" className="h-8" onClick={askReplace}>
            Replace signing secret
          </Button>
        ) : (
          <Button type="button" size="sm" variant="outline" className="h-8" onClick={makeSecret}>
            Make signing secret
          </Button>
        )}
      </div>
      {problem && <p className="text-destructive text-xs">{problem}</p>}
      <ConfirmDeleteDialog
        open={replacing}
        title="Replace the signing secret?"
        description={setup.replaceSecret ?? ""}
        confirmLabel="Replace secret"
        onConfirm={confirmReplace}
        onCancel={stopReplacing}
      />
      <TokenRevealedDialog
        token={revealed}
        onDismiss={closeSecret}
        title={SECRET_TITLE}
        description={SECRET_DESCRIPTION}
        warning={SECRET_WARNING}
      />
    </div>
  )
}

// A secret an admin pastes from the provider. A provider whose webhooks each sign with their own keeps every one, and
// they can be forgotten together.
function PastedSecret({ integrationId, rowId, setup }: { integrationId: string; rowId: string; setup: SetupState }) {
  const [secret, setSecret] = useState("")
  const [forgetting, setForgetting] = useState(false)
  const secretId = `map-events-secret-${rowId}`

  function changeSecret(event: ChangeEvent<HTMLInputElement>) {
    setSecret(event.target.value)
  }

  function clearSecret() {
    setSecret("")
  }

  function saveSecret(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    router.patch(
      mapEventsSecretIntegrationPath(integrationId),
      { environment_row_id: rowId, secret },
      { preserveScroll: true, preserveState: true, onSuccess: clearSecret },
    )
  }

  function askForget() {
    setForgetting(true)
  }

  function stopForgetting() {
    setForgetting(false)
  }

  function confirmForget() {
    router.delete(mapEventsSecretsIntegrationPath(integrationId), {
      data: { environment_row_id: rowId },
      preserveScroll: true,
      preserveState: true,
      onFinish: stopForgetting,
    })
  }

  return (
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
        (setup.forgetSecretsBlockedReason ? (
          <Tooltip>
            <TooltipTrigger asChild>
              <span className="w-fit">
                <Button type="button" size="sm" variant="outline" disabled>
                  Forget secrets
                </Button>
              </span>
            </TooltipTrigger>
            <TooltipContent>{setup.forgetSecretsBlockedReason}</TooltipContent>
          </Tooltip>
        ) : (
          <Button type="button" size="sm" variant="outline" onClick={askForget}>
            Forget secrets
          </Button>
        ))}
      <ConfirmDeleteDialog
        open={forgetting}
        title="Forget signing secrets?"
        description={setup.forgetSecrets ?? ""}
        confirmLabel="Forget secrets"
        onConfirm={confirmForget}
        onCancel={stopForgetting}
      />
    </form>
  )
}

// For a provider set up by hand: where to send its changes, how, and the secret they carry.
export function LiveUpdatesSetup({ integrationId, rowId, setup }: { integrationId: string; rowId: string; setup: SetupState }) {
  return (
    <div className="flex flex-col gap-2 pt-1">
      {setup.address ? (
        <AddressCopy address={setup.address} />
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
      {setup.makesSecret ? (
        <MadeSecret integrationId={integrationId} rowId={rowId} setup={setup} />
      ) : (
        <PastedSecret integrationId={integrationId} rowId={rowId} setup={setup} />
      )}
      <p className="text-muted-foreground text-xs">{setup.note}</p>
    </div>
  )
}
