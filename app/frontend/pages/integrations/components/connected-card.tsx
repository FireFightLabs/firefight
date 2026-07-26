import { router } from "@inertiajs/react"

import type { EnvironmentOption, Integration } from "@/types/serializers"
import type { ProviderEntry } from "@/pages/integrations/types"
import {
  integrationPath,
  retargetEnvironmentIntegrationPath,
  setAllToolsIntegrationPath,
  syncIntegrationPath,
  toggleToolIntegrationPath,
} from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Switch } from "@/components/ui/switch"
import {
  EnvironmentSelect,
  toEnvironmentId,
} from "@/pages/integrations/components/environment-select"
import { ProviderMark } from "@/pages/integrations/components/provider-mark"

const HEALTH_LABEL: Record<string, { label: string; variant: "default" | "destructive" | "secondary" }> = {
  healthy: { label: "Healthy", variant: "default" },
  failing: { label: "Failing", variant: "destructive" },
  unknown: { label: "Not checked", variant: "secondary" },
}

export function ConnectedCard({
  integration,
  provider,
  environments,
  canManage,
  onAddConnection,
}: {
  integration: Integration
  provider: ProviderEntry | undefined
  environments: EnvironmentOption[]
  canManage: boolean
  onAddConnection?: () => void
}) {
  const healthErrors = integration.environments
    .map((environment) => environment.healthError)
    .filter((message): message is string => Boolean(message))

  const enabledCount = integration.tools.filter((tool) => tool.enabled).length

  function setAllTools(enabled: boolean) {
    router.patch(setAllToolsIntegrationPath(integration.id), { enabled }, { preserveScroll: true })
  }

  function toggleTool(toolId: string) {
    router.patch(toggleToolIntegrationPath(integration.id), { tool_id: toolId }, { preserveScroll: true })
  }

  function retarget(rowId: string, value: string) {
    router.patch(
      retargetEnvironmentIntegrationPath(integration.id),
      { environment_row_id: rowId, environment_id: toEnvironmentId(value) },
      { preserveScroll: true },
    )
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between gap-3 space-y-0">
        <div className="flex items-center gap-3">
          <ProviderMark providerKey={integration.provider} mark={provider?.mark ?? "MC"} color={provider?.color ?? "#0e7490"} />
          <div>
            <CardTitle className="text-base">{integration.name}</CardTitle>
            <p className="text-muted-foreground text-xs">
              {provider?.name ?? integration.provider} · via MCP
            </p>
          </div>
        </div>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <p className="text-sm font-medium">Credentials</p>
          <div className="border-border divide-border divide-y rounded-lg border">
            {integration.environments.map((environment) => {
              const rowHealth = HEALTH_LABEL[environment.healthStatus] ?? HEALTH_LABEL.unknown
              return (
                <div key={environment.id} className="flex items-center justify-between gap-3 px-3 py-2.5">
                  <Badge variant={rowHealth.variant} className="shrink-0">
                    {rowHealth.label}
                  </Badge>
                  {canManage && environments.length > 0 ? (
                    <EnvironmentSelect
                      compact
                      value={environment.environmentId}
                      environments={environments}
                      onChange={(value) => retarget(environment.id, value)}
                    />
                  ) : (
                    <Badge variant="outline" className="shrink-0">
                      {environment.environmentName ?? "All environments"}
                    </Badge>
                  )}
                </div>
              )
            })}
          </div>
          <p className="text-muted-foreground text-xs">
            A grant scoped to an environment only matches the credentials wired to it.
          </p>
        </div>

        {healthErrors.length > 0 && (
          <div className="border-destructive/40 bg-destructive/10 text-destructive rounded-md border px-3 py-2 text-xs">
            {healthErrors[0]}
          </div>
        )}

        {integration.tools.length === 0 ? (
          <p className="text-muted-foreground text-sm">
            No tools discovered yet. Refresh to pull the server's tool list.
          </p>
        ) : (
          <div className="flex flex-col">
            <div className="flex items-center justify-between gap-3 pb-1">
              <p className="text-sm font-medium">
                Capabilities{" "}
                <span className="text-muted-foreground font-normal">
                  {enabledCount} of {integration.tools.length} on
                </span>
              </p>
              {canManage && (
                <div className="text-muted-foreground flex items-center gap-3 text-xs">
                  <button
                    type="button"
                    onClick={() => setAllTools(true)}
                    disabled={enabledCount === integration.tools.length}
                    className="hover:text-foreground disabled:pointer-events-none disabled:opacity-40"
                  >
                    Enable all
                  </button>
                  <span aria-hidden className="bg-border h-3 w-px" />
                  <button
                    type="button"
                    onClick={() => setAllTools(false)}
                    disabled={enabledCount === 0}
                    className="hover:text-foreground disabled:pointer-events-none disabled:opacity-40"
                  >
                    Disable all
                  </button>
                </div>
              )}
            </div>
            {integration.tools.map((tool) => (
              <div
                key={tool.id}
                className="border-border flex items-start justify-between gap-3 border-b py-2.5 last:border-b-0"
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium">{tool.name}</span>
                    {!tool.readOnly && (
                      <Badge variant="secondary" className="text-xs">
                        write
                      </Badge>
                    )}
                  </div>
                  <p
                    className="text-muted-foreground mt-0.5 line-clamp-2 text-xs"
                    title={tool.description ?? undefined}
                  >
                    {tool.description ?? "No description offered by the server."}
                  </p>
                  {tool.enabled && (
                    <code className="text-muted-foreground/70 mt-1 block truncate text-[11px]">
                      {tool.actionKey}
                    </code>
                  )}
                </div>
                <Switch
                  checked={tool.enabled}
                  disabled={!canManage}
                  onCheckedChange={() => toggleTool(tool.id)}
                  aria-label={`Toggle ${tool.name}`}
                />
              </div>
            ))}
          </div>
        )}

        {canManage && (
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => router.post(syncIntegrationPath(integration.id))}>
              Refresh tools
            </Button>
            {onAddConnection && (
              <Button size="sm" variant="outline" onClick={onAddConnection}>
                Add connection
              </Button>
            )}
            <Button
              size="sm"
              variant="ghost"
              className="text-destructive"
              onClick={() => router.delete(integrationPath(integration.id))}
            >
              Disconnect
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
