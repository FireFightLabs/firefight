import { router } from "@inertiajs/react"

import type { Integration } from "@/types/serializers"
import type { ProviderEntry } from "@/pages/integrations/types"
import { integrationPath, syncIntegrationPath, toggleToolIntegrationPath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Switch } from "@/components/ui/switch"
import { ProviderMark } from "@/pages/integrations/components/provider-mark"

const HEALTH_LABEL: Record<string, { label: string; variant: "default" | "destructive" | "secondary" }> = {
  healthy: { label: "Healthy", variant: "default" },
  failing: { label: "Failing", variant: "destructive" },
  unknown: { label: "Not checked", variant: "secondary" },
}

export function ConnectedCard({
  integration,
  provider,
  canManage,
}: {
  integration: Integration
  provider: ProviderEntry | undefined
  canManage: boolean
}) {
  const health = HEALTH_LABEL[integration.environments[0]?.healthStatus ?? "unknown"] ?? HEALTH_LABEL.unknown

  function toggleTool(toolId: string) {
    router.patch(toggleToolIntegrationPath(integration.id), { tool_id: toolId }, { preserveScroll: true })
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
        <Badge variant={health.variant}>{health.label}</Badge>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div className="flex flex-wrap gap-2">
          {integration.environments.map((environment) => (
            <Badge key={environment.id} variant="outline">
              {environment.environmentName ?? "All environments"}
            </Badge>
          ))}
        </div>

        {integration.tools.length === 0 ? (
          <p className="text-muted-foreground text-sm">
            No tools discovered yet. Refresh to pull the server's tool list.
          </p>
        ) : (
          <div className="flex flex-col">
            {integration.tools.map((tool) => (
              <div
                key={tool.id}
                className="border-border flex items-center justify-between gap-3 border-b py-2 last:border-b-0"
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
                  <p className="text-muted-foreground truncate text-xs">
                    {tool.enabled ? (
                      <code>{tool.actionKey}</code>
                    ) : (
                      (tool.description ?? "Enable to mint a permissioned action")
                    )}
                  </p>
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
          <div className="flex gap-2">
            <Button size="sm" variant="outline" onClick={() => router.post(syncIntegrationPath(integration.id))}>
              Refresh tools
            </Button>
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
