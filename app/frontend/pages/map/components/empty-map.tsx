import { Link } from "@inertiajs/react"
import { IconRefresh } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { integrationsPath } from "@/lib/routes"
import { EmptyState } from "@/pages/map/components/empty-state"
import { listed } from "@/pages/map/lib/words"

interface EmptyMapProps {
  syncing: boolean
  canSync: boolean
  readsIn: string[] | null
  onSync: () => void
}

export function EmptyMap({ syncing, canSync, readsIn, onSync }: EmptyMapProps) {
  if (readsIn) {
    return (
      <EmptyState
        title="Nothing you can see is on the map yet"
        text={`Nothing on the map runs in ${listed(readsIn)} yet. An admin decides which environments you see.`}
      />
    )
  }

  const title = syncing ? "The map is filling in" : "Nothing is on the map yet"
  if (syncing) {
    return (
      <EmptyState title={title} text="Firefight is reading what your connections reach. It takes a minute, and the map fills in as each one finishes.">
        {canSync && (
          <Button type="button" variant="outline" size="sm" onClick={onSync}>
            <IconRefresh className="size-4" />
            Sync now
          </Button>
        )}
      </EmptyState>
    )
  }

  if (!canSync) {
    return <EmptyState title={title} text="The map shows what runs where, read off your connections. Once an admin connects a provider, Firefight reads what runs there." />
  }

  return (
    <EmptyState
      title={title}
      text="The map shows what runs where, read off your connections. Connect a cloud, hosting or database provider and what it runs appears here, with how each part depends on the others."
    >
      <Button asChild size="sm">
        <Link href={integrationsPath()}>Connect a provider</Link>
      </Button>
    </EmptyState>
  )
}
