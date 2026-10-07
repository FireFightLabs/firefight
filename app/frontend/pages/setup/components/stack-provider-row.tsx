import { ProviderMark } from "@/components/integrations/provider-mark"
import { Button } from "@/components/ui/button"
import { INTEGRATION_CARD_STATES } from "@/lib/generated/constants"
import { cn } from "@/lib/utils"
import type { IntegrationCardRow, IntegrationProvider } from "@/types/serializers"

type RowState = IntegrationCardRow["state"]

const STATE_TONES: Record<RowState, string> = {
  [INTEGRATION_CARD_STATES.CONNECTED]: "border-success-border bg-success-tint text-success",
  [INTEGRATION_CARD_STATES.NEEDS_ATTENTION]: "border-warning-border bg-warning-tint text-warning",
  [INTEGRATION_CARD_STATES.TURNED_OFF]: "border-border bg-surface-selected text-fg-secondary",
  [INTEGRATION_CARD_STATES.NOT_CONNECTED]: "border-border bg-surface-selected text-fg-secondary",
}

// One provider and where it stands. A provider can back several connections, so a connected one still offers another,
// named after the ones it has.
export function StackProviderRow({ row, onConnect }: { row: IntegrationCardRow; onConnect: (provider: IntegrationProvider) => void }) {
  const { provider, state, connections } = row
  const connected = connections.length > 0
  const label = state === INTEGRATION_CARD_STATES.NEEDS_ATTENTION ? "Reconnect" : connected ? "Connect another" : "Connect"

  function connect() {
    onConnect(provider)
  }

  return (
    <li className="flex items-start gap-3 px-4 py-3.5 sm:items-center sm:px-5">
      <ProviderMark providerKey={provider.key} mark={provider.mark} color={provider.color} size={32} />
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-sm font-medium text-fg-primary">{provider.name}</span>
          {state !== INTEGRATION_CARD_STATES.NOT_CONNECTED && (
            <span className={cn("rounded-full border px-2 py-px text-[11px] font-medium", STATE_TONES[state])}>{row.stateLabel}</span>
          )}
        </div>
        {connected ? (
          <p className="truncate text-xs text-fg-secondary">{connections.map((connection) => connection.name).join(", ")}</p>
        ) : (
          <p className="line-clamp-2 text-xs leading-relaxed text-fg-muted">{provider.description}</p>
        )}
      </div>
      <Button size="sm" variant={connected && state !== INTEGRATION_CARD_STATES.NEEDS_ATTENTION ? "ghost" : "outline"} className="shrink-0" onClick={connect}>
        {label}
      </Button>
    </li>
  )
}
