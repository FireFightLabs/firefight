import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { ProviderMark } from "@/pages/integrations/components/provider-mark"
import { toggleIntegrationPath } from "@/lib/routes"
import type { Integration } from "@/types/serializers"
import type { ProviderEntry } from "@/pages/integrations/types"

export function ProviderTile({
  provider,
  integrations,
  canManage,
  onConnect,
  onDetails,
}: {
  provider: ProviderEntry
  integrations: Integration[]
  canManage: boolean
  onConnect: (provider: ProviderEntry) => void
  onDetails: (integration: Integration) => void
}) {
  // One connection stays the plain Details-plus-switch tile; several become a
  // list, since a provider backing two accounts has no single on/off state.
  const single = integrations.length === 1 ? integrations[0] : null
  const connected = integrations.length > 0

  function toggle(integration: Integration) {
    router.patch(toggleIntegrationPath(integration.id), {}, { preserveScroll: true })
  }

  return (
    <div className="border-border bg-card flex h-full flex-col rounded-xl border p-6">
      <div className="flex items-start gap-4">
        <ProviderMark providerKey={provider.key} mark={provider.mark} color={provider.color} size={48} />
        <div className="min-w-0 flex-1">
          <div className="text-[15px] font-semibold">{provider.name}</div>
          <p className="text-muted-foreground mt-1 line-clamp-2 text-[13px] leading-relaxed">
            {provider.description}
          </p>
        </div>
      </div>

      {integrations.length > 1 && (
        <div className="border-border divide-border mt-4 divide-y rounded-lg border">
          {integrations.map((integration) => (
            <div key={integration.id} className="flex items-center justify-between gap-2 px-3 py-2">
              <button
                type="button"
                onClick={() => onDetails(integration)}
                className="min-w-0 truncate text-left text-sm hover:underline"
              >
                {integration.name}
              </button>
              <Switch
                checked={!integration.disabled}
                disabled={!canManage}
                onCheckedChange={() => toggle(integration)}
                aria-label={`Toggle ${integration.name}`}
              />
            </div>
          ))}
        </div>
      )}

      <div className="mt-auto flex items-center justify-between gap-2 pt-6">
        <div className="flex items-center gap-2">
          {single && (
            <Button size="sm" variant="outline" onClick={() => onDetails(single)}>
              Details
            </Button>
          )}
          {!connected && (
            <Button size="sm" variant="outline" disabled={!canManage} onClick={() => onConnect(provider)}>
              Connect
            </Button>
          )}
          {connected && canManage && (
            <Button size="sm" variant="ghost" onClick={() => onConnect(provider)}>
              Add connection
            </Button>
          )}
        </div>
        {integrations.length <= 1 && (
          <Switch
            checked={single !== null && !single.disabled}
            disabled={!canManage}
            onCheckedChange={() => (single ? toggle(single) : onConnect(provider))}
            aria-label={single ? `Toggle ${provider.name}` : `Connect ${provider.name}`}
          />
        )}
      </div>
    </div>
  )
}
