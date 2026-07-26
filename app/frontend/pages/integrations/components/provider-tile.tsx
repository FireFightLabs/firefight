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
    <div className="group border-border bg-card hover:border-primary/40 flex h-full flex-col rounded-xl border p-4 transition-colors">
      <div className="flex items-center gap-3">
        <ProviderMark mark={provider.mark} color={provider.color} size={36} />
        <div className="min-w-0 flex-1">
          <div className="truncate text-sm font-semibold">{provider.name}</div>
          {provider.serverUrl && (
            <div className="text-muted-foreground text-xs">Official MCP server</div>
          )}
        </div>
        <Button
          size="sm"
          variant="outline"
          disabled={!canManage}
          onClick={() => onConnect(provider)}
          className="opacity-70 transition-opacity group-hover:opacity-100"
        >
          Connect
        </Button>
      </div>
      <p className="text-muted-foreground mt-3 text-[13px] leading-snug">{provider.description}</p>
    </div>
  )
}
