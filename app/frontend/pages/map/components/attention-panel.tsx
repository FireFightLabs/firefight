import { IconAlertTriangle } from "@tabler/icons-react"

import { RESOURCE_MAP_CHANGE_WINDOW_HOURS } from "@/lib/generated/constants"
import { shortAgo } from "@/lib/time"
import { LinkSuggestion } from "@/pages/map/components/link-suggestion"
import { LiveRow } from "@/pages/map/components/live-row"
import { PanelSection } from "@/pages/map/components/panel-section"
import { PickRow } from "@/pages/map/components/pick-row"
import { StatCount } from "@/pages/map/components/stat-count"
import { accountOf } from "@/pages/map/lib/graph"
import { changeLabel } from "@/pages/map/lib/labels"
import type {
  ResourceMapChange,
  ResourceMapConnection,
  ResourceMapLink,
  ResourceMapResource,
} from "@/types/serializers"

interface AttentionPanelProps {
  resources: ResourceMapResource[]
  links: ResourceMapLink[]
  changes: ResourceMapChange[]
  connections: ResourceMapConnection[]
  canCurate: boolean
  onPick: (resourceId: string) => void
}

// What someone opening the map should look at first: what is broken, what just changed, and what waits on them.
export function AttentionPanel({ resources, links, changes, connections, canCurate, onPick }: AttentionPanelProps) {
  const byId = new Map(resources.map((resource) => [ resource.id, resource ]))
  const burning = resources.filter((resource) => resource.openIncidents.length > 0)
  const toReview = links.filter((link) => link.unconfirmed)
  const linked = new Set(links.flatMap((link) => [ link.fromId, link.toId ]))
  const alone = resources.filter((resource) => !linked.has(resource.id))
  const unread = connections.filter((connection) => connection.error || connection.baselineError || connection.logPatternsError || connection.gaps.length > 0)
  const accounts = new Set(resources.map((resource) => accountOf(resource).key))
  const live = connections.filter((connection) => connection.liveUpdates)

  return (
    <aside className="flex flex-col gap-6 overflow-y-auto border-t border-border bg-card/40 p-5 lg:border-t-0 lg:border-l" aria-label="What needs attention">
      <PanelSection title="Needs attention now">
        {burning.length === 0 && <p className="text-sm text-muted-foreground">No open incident touches anything on the map.</p>}
        {burning.flatMap((resource) =>
          resource.openIncidents.map((incident) => (
            <PickRow key={`${resource.id}:${incident.id}`} resourceId={resource.id} onPick={onPick} tone="danger">
              <span className="font-semibold">{incident.identifier} on {resource.name}</span>
              <span className="text-xs text-destructive">{incident.name}</span>
            </PickRow>
          )),
        )}
      </PanelSection>

      <PanelSection title={`Changed in the last ${RESOURCE_MAP_CHANGE_WINDOW_HOURS} hours`}>
        {changes.length === 0 && <p className="text-sm text-muted-foreground">Nothing changed.</p>}
        {changes.slice(0, 8).map((change) => (
          <PickRow key={change.id} resourceId={change.resourceId} onPick={onPick}>
            <span className="flex justify-between gap-3">
              <span>{changeLabel(change)}</span>
              <span className="shrink-0 text-muted-foreground tabular-nums">{shortAgo(change.happenedAt)}</span>
            </span>
          </PickRow>
        ))}
      </PanelSection>

      <PanelSection title="To review">
        {toReview.length === 0 && alone.length === 0 && <p className="text-sm text-muted-foreground">Nothing waits on you.</p>}
        {toReview.map((link) => (
          <LinkSuggestion key={link.id} link={link} byId={byId} canCurate={canCurate} />
        ))}
        {alone.length > 0 && (
          <p className="text-sm text-muted-foreground">
            {alone.length === 1 ? "1 resource has" : `${alone.length} resources have`} no links: {alone.map((resource) => resource.name).join(", ")}.
          </p>
        )}
      </PanelSection>

      {live.length > 0 && (
        <PanelSection title="Live updates">
          {live.map((connection) => (
            <LiveRow key={connection.id} connection={connection} />
          ))}
        </PanelSection>
      )}

      {unread.length > 0 && (
        <PanelSection title="Not read">
          {unread.map((connection) => (
            <div key={connection.id} className="edge-bar flex gap-2.5 rounded-lg bg-warning-tint px-3 py-2 [--edge-bar:var(--warning)] text-sm text-fg-primary">
              <IconAlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" />
              <span className="flex flex-col gap-1">
                <span className="font-medium">{connection.name}</span>
                {connection.error && <span className="text-xs text-muted-foreground">The last sync failed: {connection.error}</span>}
                {connection.baselineError && (
                  <span className="text-xs text-muted-foreground">What normal looks like could not be read: {connection.baselineError}</span>
                )}
                {connection.logPatternsError && (
                  <span className="text-xs text-muted-foreground">The usual log lines could not be read: {connection.logPatternsError}</span>
                )}
                {connection.gaps.map((gap) => (
                  <span key={gap} className="text-xs text-muted-foreground">{gap}</span>
                ))}
              </span>
            </div>
          ))}
        </PanelSection>
      )}

      <section className="grid grid-cols-3 gap-2">
        <StatCount value={resources.length} label="Resources" />
        <StatCount value={links.length} label="Links" />
        <StatCount value={accounts.size} label="Accounts" />
      </section>
    </aside>
  )
}
