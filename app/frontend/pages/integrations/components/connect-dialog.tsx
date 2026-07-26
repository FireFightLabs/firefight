import { useEffect, useState } from "react"
import { router } from "@inertiajs/react"
import { IconArrowLeft } from "@tabler/icons-react"

import type { EnvironmentOption, ProviderEntry } from "@/pages/integrations/types"
import { integrationsPath, oauthStartIntegrationsPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
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

function oauthHref(providerKey: string, name: string, environmentId: string) {
  const params = new URLSearchParams({ provider: providerKey })
  if (name) params.set("name", name)
  if (environmentId !== NO_ENVIRONMENT) params.set("environment_id", environmentId)
  return `${oauthStartIntegrationsPath()}?${params.toString()}`
}

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
  const [separateAccount, setSeparateAccount] = useState(false)

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
    setSeparateAccount(false)
  }, [provider])

  function toggleSeparateAccount() {
    const next = !separateAccount
    setSeparateAccount(next)
    setName(next ? "" : (provider?.name ?? ""))
  }

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
      <DialogContent className="sm:max-w-md">
        <DialogHeader className="items-center gap-0 text-center sm:text-center">
          {provider && (
            <ProviderMark providerKey={provider.key} mark={provider.mark} color={provider.color} size={52} />
          )}
          <DialogTitle className="mt-3 text-lg">Connect {provider?.name}</DialogTitle>
          <DialogDescription className="mx-auto max-w-xs leading-relaxed">
            Firefight discovers this server's tools and you pick which to enable. Nothing turns on
            automatically.
          </DialogDescription>
        </DialogHeader>

        {provider && oauthAvailable && !useToken && (
          <div className="flex flex-col gap-3 pt-1">
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
                <p className="text-muted-foreground text-xs">
                  Connect once per environment to give each its own credentials, then scope who can
                  reach which.
                </p>
              </div>
            )}

            {separateAccount && (
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="oauth-name">Connection name</Label>
                <Input
                  id="oauth-name"
                  value={name}
                  onChange={(event) => setName(event.target.value)}
                  placeholder={`e.g. ${provider.name} Payments`}
                />
                <p className="text-muted-foreground text-xs">
                  Its tools get their own permissions, kept separate from {provider.name}.
                </p>
              </div>
            )}

            {separateAccount && !name.trim() ? (
              <Button size="lg" className="w-full" disabled>
                Continue with {provider.name}
              </Button>
            ) : (
              <Button asChild size="lg" className="w-full">
                <a href={oauthHref(provider.key, name, environmentId)}>
                  Continue with {provider.name}
                </a>
              </Button>
            )}
            <p className="text-muted-foreground text-center text-xs">
              You approve access on {provider.name}'s consent screen. No keys to copy.
            </p>
            <div className="flex flex-col items-center gap-1.5">
              <button
                type="button"
                onClick={toggleSeparateAccount}
                className="text-muted-foreground hover:text-foreground text-xs underline underline-offset-4"
              >
                {separateAccount ? "This is my only account" : "Connecting a second account?"}
              </button>
              <button
                type="button"
                onClick={() => setUseToken(true)}
                className="text-muted-foreground hover:text-foreground text-xs underline underline-offset-4"
              >
                Connect with a token instead
              </button>
            </div>
          </div>
        )}

        {showManualForm && (
          <div className="flex flex-col gap-4 pt-1">
            {oauthAvailable && (
              <button
                type="button"
                onClick={() => setUseToken(false)}
                className="text-muted-foreground hover:text-foreground -mt-1 flex items-center gap-1 self-start text-xs"
              >
                <IconArrowLeft className="size-3.5" />
                Back to one-click connect
              </button>
            )}
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
                Stored encrypted and scoped to this connection. Never shared with agents or shown again.
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
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="outline" onClick={onDismiss}>
                Cancel
              </Button>
              <Button onClick={submit} disabled={submitting || !name || !serverUrl}>
                Connect &amp; discover tools
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
