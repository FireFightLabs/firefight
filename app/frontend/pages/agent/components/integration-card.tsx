import { usePage } from "@inertiajs/react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { ConnectDialog } from "@/components/integrations/connect-dialog"
import { ProviderMark } from "@/components/integrations/provider-mark"
import { INTEGRATION_CARD_STATES, INTEGRATION_DETAILS_QUERY_PARAM } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { agentChatPath, integrationsPath } from "@/lib/routes"
import type { AgentPageProps } from "@/pages/agent/types"
import type { IntegrationCardRow, IntegrationProvider } from "@/types/serializers"

// Past this many rows a category is easier to search than to scan.
const FILTER_FROM = 8

type CardState = IntegrationCardRow["state"]

const STATE_LABELS: Record<CardState, string> = {
  [INTEGRATION_CARD_STATES.CONNECTED]: "Connected",
  [INTEGRATION_CARD_STATES.NEEDS_ATTENTION]: "Needs attention",
  [INTEGRATION_CARD_STATES.TURNED_OFF]: "Turned off",
  [INTEGRATION_CARD_STATES.NOT_CONNECTED]: "Not connected",
}

const STATE_TONES: Record<CardState, string> = {
  [INTEGRATION_CARD_STATES.CONNECTED]: "bg-green-tint text-green",
  [INTEGRATION_CARD_STATES.NEEDS_ATTENTION]: "bg-orange-tint text-orange",
  [INTEGRATION_CARD_STATES.TURNED_OFF]: "bg-hover-2 text-ink-2",
  [INTEGRATION_CARD_STATES.NOT_CONNECTED]: "bg-hover-2 text-ink-2",
}

// Connecting a provider that is not connected, or connecting again one whose credentials stopped working.
const OPENS_DIALOG: CardState[] = [ INTEGRATION_CARD_STATES.NOT_CONNECTED, INTEGRATION_CARD_STATES.NEEDS_ATTENTION ]

interface IntegrationCardProps {
  category: string
}

// The rows come from the page, read fresh on every visit, so coming back from connecting shows the new state.
export function IntegrationCard({ category }: IntegrationCardProps) {
  const { integrationCards, environments, conversation } = usePage<AgentPageProps>().props
  const canConnect = useCan("integrations")
  const [ connecting, setConnecting ] = useState<IntegrationProvider | null>(null)
  const [ filter, setFilter ] = useState("")
  const card = integrationCards.find((candidate) => candidate.category === category)
  if (!card) {
    return null
  }

  const wanted = filter.trim().toLowerCase()
  const rows = card.rows.filter((row) => row.provider.name.toLowerCase().includes(wanted))
  const existingNames = card.rows.find((row) => row.provider.key === connecting?.key)?.connections.map((connection) => connection.name) ?? []
  const returnTo = conversation ? agentChatPath(conversation.id) : undefined

  function stopConnecting() {
    setConnecting(null)
  }

  return (
    <section className="flex w-full max-w-110 flex-col overflow-hidden rounded-card bg-surface shadow-card" aria-label={`${card.name} integrations`}>
      <header className="flex flex-col gap-0.5 border-b border-line px-3.5 py-3">
        <h3 className="text-[13.5px] font-semibold text-ink">{card.name}</h3>
        <p className="text-[12.5px] text-ink-2">{card.tagline}</p>
      </header>

      {card.rows.length > FILTER_FROM && (
        <input
          type="search"
          value={filter}
          onChange={(event) => setFilter(event.target.value)}
          placeholder={`Search ${card.name.toLowerCase()} integrations`}
          aria-label={`Search ${card.name} integrations`}
          className="border-b border-line px-3.5 py-2 text-[13px] text-ink placeholder:text-ink-3"
        />
      )}

      <ul className="flex flex-col">
        {rows.map((row) => (
          <CardRow key={row.provider.key} row={row} canConnect={canConnect} onConnect={setConnecting} />
        ))}
        {rows.length === 0 && <li className="px-3.5 py-3 text-[12.5px] text-ink-3">Nothing matches that.</li>}
      </ul>

      <a href={integrationsPath()} className="border-t border-line px-3.5 py-2.5 text-[12.5px] text-ink-2 hover:text-ink">
        See all integrations
      </a>

      <ConnectDialog
        provider={connecting}
        environments={environments}
        existingNames={existingNames}
        returnTo={returnTo}
        onDismiss={stopConnecting}
      />
    </section>
  )
}

interface CardRowProps {
  row: IntegrationCardRow
  canConnect: boolean
  onConnect: (provider: IntegrationProvider) => void
}

function CardRow({ row, canConnect, onConnect }: CardRowProps) {
  const { provider, state } = row

  function connect() {
    onConnect(provider)
  }

  return (
    <li className="flex items-center gap-3 border-b border-line px-3.5 py-2.5 last:border-0">
      <ProviderMark providerKey={provider.key} mark={provider.mark} color={provider.color} size={30} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-[13px] font-medium text-ink">{provider.name}</span>
          <span className={`shrink-0 rounded-full px-2 py-px text-[11px] font-medium ${STATE_TONES[state]}`}>
            {STATE_LABELS[state]}
          </span>
        </div>
        <p className="truncate text-[12px] text-ink-2">{provider.description}</p>
      </div>
      <RowAction row={row} canConnect={canConnect} onConnect={connect} />
    </li>
  )
}

interface RowActionProps {
  row: IntegrationCardRow
  canConnect: boolean
  onConnect: () => void
}

function detailsPath(id: string) {
  return integrationsPath({ [INTEGRATION_DETAILS_QUERY_PARAM]: id })
}

// One connection is managed from its own details. A provider backing several accounts names each, so none is hidden.
function RowAction({ row, canConnect, onConnect }: RowActionProps) {
  const { state, connections } = row
  if (!OPENS_DIALOG.includes(state)) {
    if (connections.length === 1) {
      return (
        <a href={detailsPath(connections[0].id)} className="shrink-0 text-[12.5px] text-ink-2 hover:text-ink">
          Manage
        </a>
      )
    }

    return (
      <div className="flex shrink-0 flex-col items-end gap-0.5">
        {connections.map((connection) => (
          <a key={connection.id} href={detailsPath(connection.id)} className="text-[12.5px] text-ink-2 hover:text-ink">
            {connection.name}
          </a>
        ))}
      </div>
    )
  }
  if (!canConnect) {
    return <span className="shrink-0 text-[12px] text-ink-3">An admin can connect this</span>
  }

  return (
    <Button size="sm" variant={state === INTEGRATION_CARD_STATES.NOT_CONNECTED ? "primary" : "secondary"} onClick={onConnect}>
      {state === INTEGRATION_CARD_STATES.NOT_CONNECTED ? "Connect" : "Reconnect"}
    </Button>
  )
}
