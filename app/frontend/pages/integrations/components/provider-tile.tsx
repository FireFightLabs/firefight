import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { ProviderMark } from "@/pages/integrations/components/provider-mark"
import { toggleIntegrationPath } from "@/lib/routes"
import type { Integration } from "@/types/serializers"
import type { ProviderEntry } from "@/pages/integrations/types"

export function ProviderTile({
  provider,
  integration,
  canManage,
  onConnect,
  onDetails,
}: {
  provider: ProviderEntry
  integration: Integration | null
  canManage: boolean
  onConnect: (provider: ProviderEntry) => void
  onDetails: (integration: Integration) => void
}) {
  const connected = integration !== null
  const enabled = connected && !integration.disabled

  function handleToggle() {
    if (!canManage) return
    if (connected) {
      router.patch(toggleIntegrationPath(integration.id), {}, { preserveScroll: true })
    } else {
      onConnect(provider)
    }
  }

  return (
    <div className="border-border bg-card flex h-full flex-col rounded-xl border p-5">
      <div className="flex items-start gap-4">
        <ProviderMark providerKey={provider.key} mark={provider.mark} color={provider.color} size={44} />
        <div className="min-w-0">
          <div className="text-[15px] font-semibold">{provider.name}</div>
          <p className="text-muted-foreground mt-0.5 line-clamp-2 text-[13px] leading-snug">
            {provider.description}
          </p>
        </div>
      </div>
      <div className="mt-5 flex items-center justify-between">
        {connected ? (
          <Button size="sm" variant="outline" onClick={() => onDetails(integration)}>
            Details
          </Button>
        ) : (
          <Button size="sm" variant="outline" disabled={!canManage} onClick={() => onConnect(provider)}>
            Connect
          </Button>
        )}
        <Switch
          checked={enabled}
          disabled={!canManage}
          onCheckedChange={handleToggle}
          aria-label={connected ? `Toggle ${provider.name}` : `Connect ${provider.name}`}
        />
      </div>
    </div>
  )
}
