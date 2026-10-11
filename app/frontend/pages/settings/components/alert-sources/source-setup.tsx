import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconCheck, IconCopy, IconRefresh } from "@tabler/icons-react"

import type { AlertSourceSettings } from "@/types/serializers"
import { regenerateAddressAlertSourcePath, tokenAlertSourcePath } from "@/lib/routes"
import { postJson } from "@/lib/http"
import { fetchSourceAddress, type AlertProviderSetup } from "@/pages/settings/lib/alerts"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

const COPIED_FOR_MS = 1500

type CopiedField = "url" | "token" | "template"

// Where to paste the URL and the token in the tool, step by step. A tool that signs with a secret of its own gets a
// field to paste that secret into instead of a token to copy.
export function SourceSetup({
  source,
  setup,
  secret,
  onSecretChange,
}: {
  source: AlertSourceSettings
  setup: AlertProviderSetup | null
  secret: string
  onSecretChange: (value: string) => void
}) {
  const [copied, setCopied] = useState<CopiedField | null>(null)
  const [confirmingNewAddress, setConfirmingNewAddress] = useState(false)
  const ingestUrl = `${window.location.origin}${source.ingestPath}`
  const secretInAddress = setup?.secretInAddress ?? false

  function markCopied(field: CopiedField) {
    setCopied(field)
    setTimeout(() => setCopied(null), COPIED_FOR_MS)
  }

  // A URL holding the source's secret is fetched whole only when copied, as the page holds it masked.
  async function copyUrl() {
    const url = secretInAddress ? await fetchSourceAddress(source.id) : ingestUrl
    if (url) {
      await navigator.clipboard.writeText(url)
      markCopied("url")
    }
  }

  function askForNewAddress() {
    setConfirmingNewAddress(true)
  }

  function cancelNewAddress() {
    setConfirmingNewAddress(false)
  }

  // State is kept so the dialog this sits in stays open with any edits in it.
  function regenerateAddress() {
    setConfirmingNewAddress(false)
    router.post(regenerateAddressAlertSourcePath(source.id), {}, { preserveState: true, preserveScroll: true })
  }

  function copyTemplate() {
    if (setup?.template) {
      void navigator.clipboard.writeText(setup.template).then(() => markCopied("template"))
    }
  }

  // The token is fetched on demand so it never ships in page props.
  async function copyToken() {
    try {
      const { ok, data } = await postJson<{ token: string }>(tokenAlertSourcePath(source.id))
      if (ok && data) {
        await navigator.clipboard.writeText(data.token)
        markCopied("token")
      }
    } catch {
      // The button stays as it was and the user can retry.
    }
  }

  return (
    <div className="flex min-w-0 flex-col gap-3 rounded-md border border-border bg-muted/40 p-3 text-xs text-muted-foreground">
      <p className="font-medium text-foreground">Setup{setup ? ` for ${setup.label}` : ""}</p>
      <div className="flex flex-wrap items-center gap-2">
        <p className="w-full min-w-0 break-all font-mono sm:w-auto sm:flex-1">{ingestUrl}</p>
        <Button type="button" variant="outline" size="sm" className="h-7 gap-1.5 px-2 text-xs" onClick={() => void copyUrl()}>
          {copied === "url" ? <IconCheck className="size-3.5" /> : <IconCopy className="size-3.5" />}
          Copy URL
        </Button>
        {secretInAddress && (
          <Button type="button" variant="outline" size="sm" className="h-7 gap-1.5 px-2 text-xs" onClick={askForNewAddress}>
            <IconRefresh className="size-3.5" />
            Regenerate address
          </Button>
        )}
        {!setup?.secretFromProvider && !secretInAddress && (
          <Button type="button" variant="outline" size="sm" className="h-7 gap-1.5 px-2 text-xs" onClick={() => void copyToken()}>
            {copied === "token" ? <IconCheck className="size-3.5" /> : <IconCopy className="size-3.5" />}
            Copy token
          </Button>
        )}
      </div>
      {setup && setup.steps.length > 0 && (
        <ol className="flex list-decimal flex-col gap-1.5 pl-4">
          {setup.steps.map((step) => (
            <li key={step}>{step}</li>
          ))}
        </ol>
      )}
      {setup?.template && (
        <div className="flex min-w-0 flex-col gap-1.5">
          <div className="flex items-center justify-between gap-2">
            <p className="font-medium text-foreground">Payload template</p>
            <Button type="button" variant="outline" size="sm" className="h-7 gap-1.5 px-2 text-xs" onClick={copyTemplate}>
              {copied === "template" ? <IconCheck className="size-3.5" /> : <IconCopy className="size-3.5" />}
              Copy template
            </Button>
          </div>
          <pre className="max-h-48 w-full max-w-full overflow-auto rounded-md border border-border bg-background p-2 font-mono text-[11px] leading-relaxed text-foreground">
            {setup.template}
          </pre>
        </div>
      )}
      {setup?.secretFromProvider && (
        <div className="flex min-w-0 flex-col gap-1.5">
          <Label htmlFor="source-secret" className="text-foreground">Signing secret from {setup.label}</Label>
          <Input
            id="source-secret"
            type="password"
            autoComplete="off"
            value={secret}
            onChange={(event) => onSecretChange(event.target.value)}
            placeholder={source.secretSummary ? "Leave empty to keep the saved secret" : "Paste the secret here"}
          />
          <p>{source.secretSummary ?? `No secret saved yet. Firefight refuses alerts from ${setup.label} until you save one.`}</p>
        </div>
      )}
      {secretInAddress && (
        <p>The URL holds this source's secret, so it shows masked here and is copied whole.</p>
      )}
      <ConfirmDeleteDialog
        open={confirmingNewAddress}
        title={`Regenerate the address of ${source.name}?`}
        description={`The old address stops working at once. Paste the new one into ${setup?.label ?? "the tool"}, or its alerts are refused.`}
        confirmLabel="Regenerate address"
        onConfirm={regenerateAddress}
        onCancel={cancelNewAddress}
      />
    </div>
  )
}
