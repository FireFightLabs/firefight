import { Button } from "@/components/ui/button"
import { ProviderMark } from "@/pages/integrations/components/provider-mark"
import type { ProviderEntry } from "@/pages/integrations/types"

export function ProviderTile({
  provider,
  canManage,
  onConnect,
}: {
  provider: ProviderEntry
  canManage: boolean
  onConnect: (provider: ProviderEntry) => void
}) {
  return (
    <div className="group border-border bg-card hover:border-primary/50 flex h-full flex-col gap-3 rounded-xl border p-5 transition-colors">
      <div className="flex items-start justify-between gap-3">
        <ProviderMark providerKey={provider.key} mark={provider.mark} color={provider.color} size={44} />
        <Button
          size="sm"
          variant="outline"
          disabled={!canManage}
          onClick={() => onConnect(provider)}
          className="text-muted-foreground group-hover:border-primary/50 group-hover:text-foreground transition-colors"
        >
          Connect
        </Button>
      </div>
      <div className="flex flex-col gap-1">
        <div className="flex items-baseline gap-2">
          <span className="text-sm font-semibold">{provider.name}</span>
          {provider.serverUrl && <span className="text-primary text-[11px] font-medium">Official MCP</span>}
        </div>
        <p className="text-muted-foreground line-clamp-2 text-[13px] leading-snug">{provider.description}</p>
      </div>
    </div>
  )
}
