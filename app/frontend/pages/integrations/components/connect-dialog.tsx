import { useEffect, useState } from "react"
import { router } from "@inertiajs/react"

import type { EnvironmentOption, ProviderEntry } from "@/pages/integrations/types"
import { integrationsPath, oauthStartIntegrationsPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { ProviderMark } from "@/pages/integrations/components/provider-mark"

const NO_ENVIRONMENT = "none"

export function ConnectDialog({
  provider,
  environments,
  onDismiss,
}: {
  provider: ProviderEntry | null
  environments: EnvironmentOption[]
  onDismiss: () => void
}) {
  const [name, setName] = useState("")
  const [serverUrl, setServerUrl] = useState("")
  const [authorization, setAuthorization] = useState("")
  const [environmentId, setEnvironmentId] = useState(NO_ENVIRONMENT)
  const [submitting, setSubmitting] = useState(false)
  const [useToken, setUseToken] = useState(false)

  const oauthAvailable = provider !== null && provider.serverUrl !== ""
  const showManualForm = !oauthAvailable || useToken

  useEffect(() => {
    if (!provider) return
    setName(provider.key === "custom_mcp" ? "" : provider.name)
    setServerUrl(provider.serverUrl)
    setAuthorization("")
    setEnvironmentId(NO_ENVIRONMENT)
    setSubmitting(false)
    setUseToken(false)
  }, [provider])

  function submit() {
    if (!provider) return
    setSubmitting(true)
    router.post(
      integrationsPath(),
      {
        provider: provider.key,
        name,
        server_url: serverUrl,
        authorization,
        environment_id: environmentId === NO_ENVIRONMENT ? "" : environmentId,
      },
      { onFinish: () => onDismiss() },
    )
  }

  return (
    <Dialog open={provider !== null} onOpenChange={(open) => { if (!open) onDismiss() }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <div className="flex items-center gap-3">
            {provider && <ProviderMark providerKey={provider.key} mark={provider.mark} color={provider.color} size={36} />}
            <div>
              <DialogTitle>Connect {provider?.name}</DialogTitle>
              <DialogDescription>
                Firefight discovers the server's tools and you choose which ones to enable. Nothing is
                enabled automatically.
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        {provider && oauthAvailable && (
          <div className="flex flex-col gap-3">
            <Button asChild className="w-full">
              <a href={`${oauthStartIntegrationsPath()}?provider=${provider.key}`}>
                Continue with {provider.name}
              </a>
            </Button>
            <p className="text-muted-foreground text-center text-xs">
              You approve access on {provider.name}'s consent screen. No keys to copy.
            </p>
            {!useToken && (
              <button
                type="button"
                onClick={() => setUseToken(true)}
                className="text-muted-foreground hover:text-foreground text-center text-xs underline underline-offset-2"
              >
                Connect with a token instead
              </button>
            )}
          </div>
        )}

        {showManualForm && (
        <div className="flex flex-col gap-4">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="connect-name">Connection name</Label>
            <Input
              id="connect-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder={provider?.key === "custom_mcp" ? "e.g. Internal tools" : provider?.name}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="connect-url">MCP server URL</Label>
            <Input
              id="connect-url"
              value={serverUrl}
              onChange={(event) => setServerUrl(event.target.value)}
              placeholder="https://example.com/mcp"
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="connect-auth">Authorization header</Label>
            <Input
              id="connect-auth"
              type="password"
              value={authorization}
              onChange={(event) => setAuthorization(event.target.value)}
              placeholder="Bearer …  (optional, use a read-only key)"
            />
            <p className="text-muted-foreground text-xs">
              Stored encrypted, scoped to this connection. Never shared with agents or shown again.
            </p>
          </div>
          {environments.length > 0 && (
            <div className="flex flex-col gap-1.5">
              <Label>Environment these credentials reach</Label>
              <Select value={environmentId} onValueChange={setEnvironmentId}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={NO_ENVIRONMENT}>All environments</SelectItem>
                  {environments.map((environment) => (
                    <SelectItem key={environment.id} value={environment.id}>
                      {environment.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
        </div>
        )}

        <DialogFooter>
          <Button variant="outline" onClick={onDismiss}>
            Cancel
          </Button>
          {showManualForm && (
            <Button onClick={submit} disabled={submitting || !name || !serverUrl}>
              Connect &amp; discover tools
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
