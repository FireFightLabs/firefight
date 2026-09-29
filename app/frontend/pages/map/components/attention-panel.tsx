import { router } from "@inertiajs/react"
import { IconAlertTriangle } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { confirmResourceMapLinkPath, dismissResourceMapLinkPath } from "@/lib/routes"
import { changeLabel, RELATION_SENTENCES } from "@/pages/map/lib/labels"
import { shortAgo } from "@/pages/map/lib/time"
import type {
  ResourceMapChange,
  ResourceMapConnection,
  ResourceMapLink,
  ResourceMapResource,
} from "@/types/serializers"

const VISIT = { preserveScroll: true, preserveState: true }

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
  const unread = connections.filter((connection) => connection.error || connection.gaps.length > 0)
  const accounts = new Set(resources.map((resource) => `${resource.provider}:${resource.account}`))

  return (
    <aside className="flex flex-col gap-6 overflow-y-auto border-t border-border bg-card/40 p-5 lg:border-t-0 lg:border-l" aria-label="What needs attention">
      <Section title="Needs attention now">
        {burning.length === 0 && <p className="text-sm text-muted-foreground">No open incident touches anything on the map.</p>}
        {burning.flatMap((resource) =>
          resource.openIncidents.map((incident) => (
            <PickRow key={`${resource.id}:${incident.id}`} resourceId={resource.id} onPick={onPick} tone="danger">
              <span className="font-semibold">{incident.identifier} on {resource.name}</span>
              <span className="text-xs text-destructive">{incident.name}</span>
            </PickRow>
          )),
        )}
      </Section>

      <Section title="Changed in the last 24 hours">
        {changes.length === 0 && <p className="text-sm text-muted-foreground">Nothing changed.</p>}
        {changes.slice(0, 8).map((change) => (
          <PickRow key={change.id} resourceId={change.resourceId} onPick={onPick}>
            <span className="flex justify-between gap-3">
              <span>{changeLabel(change)}</span>
              <span className="shrink-0 text-muted-foreground tabular-nums">{shortAgo(change.happenedAt)}</span>
            </span>
          </PickRow>
        ))}
      </Section>

      <Section title="To review">
        {toReview.length === 0 && alone.length === 0 && <p className="text-sm text-muted-foreground">Nothing waits on you.</p>}
        {toReview.map((link) => (
          <Suggestion key={link.id} link={link} byId={byId} canCurate={canCurate} />
        ))}
        {alone.length > 0 && (
          <p className="text-sm text-muted-foreground">
            {alone.length === 1 ? "1 resource has" : `${alone.length} resources have`} no links: {alone.map((resource) => resource.name).join(", ")}.
          </p>
        )}
      </Section>

      {unread.length > 0 && (
        <Section title="Not read">
          {unread.map((connection) => (
            <div key={connection.id} className="flex gap-2.5 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm">
              <IconAlertTriangle className="mt-0.5 size-4 shrink-0 text-amber-400" />
              <span className="flex flex-col gap-1">
                <span className="font-medium">{connection.name}</span>
                {connection.error && <span className="text-xs text-muted-foreground">The last sync failed: {connection.error}</span>}
                {connection.gaps.map((gap) => (
                  <span key={gap} className="text-xs text-muted-foreground">{gap}</span>
                ))}
              </span>
            </div>
          ))}
        </Section>
      )}

      <section className="grid grid-cols-3 gap-2">
        <Count value={resources.length} label="Resources" />
        <Count value={links.length} label="Links" />
        <Count value={accounts.size} label="Accounts" />
      </section>
    </aside>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-2.5">
      <h2 className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">{title}</h2>
      {children}
    </section>
  )
}

interface PickRowProps {
  resourceId: string
  onPick: (resourceId: string) => void
  tone?: "danger"
  children: React.ReactNode
}

function PickRow({ resourceId, onPick, tone, children }: PickRowProps) {
  function pick() {
    onPick(resourceId)
  }

  return (
    <button
      type="button"
      onClick={pick}
      className={`flex flex-col gap-0.5 rounded-lg px-3 py-2 text-left text-sm transition-colors ${
        tone ? "border border-destructive/40 bg-destructive/10 hover:bg-destructive/15" : "hover:bg-muted/50"
      }`}
    >
      {children}
    </button>
  )
}

function Suggestion({ link, byId, canCurate }: { link: ResourceMapLink; byId: Map<string, ResourceMapResource>; canCurate: boolean }) {
  function confirm() {
    router.post(confirmResourceMapLinkPath(link.id), {}, VISIT)
  }

  function dismiss() {
    router.post(dismissResourceMapLinkPath(link.id), {}, VISIT)
  }

  return (
    <div className="flex flex-col gap-2 rounded-lg border border-dashed border-primary/50 bg-primary/5 px-3 py-2.5 text-sm">
      <span>
        Halon suggests <b className="font-semibold">{byId.get(link.fromId)?.name}</b> {RELATION_SENTENCES[link.relation]}{" "}
        <b className="font-semibold">{byId.get(link.toId)?.name}</b>
        {link.note ? `, from ${link.note}` : "."}
      </span>
      {canCurate && (
        <div className="flex gap-2">
          <Button type="button" size="sm" onClick={confirm}>
            Confirm link
          </Button>
          <Button type="button" size="sm" variant="outline" onClick={dismiss}>
            Dismiss
          </Button>
        </div>
      )}
    </div>
  )
}

function Count({ value, label }: { value: number; label: string }) {
  return (
    <div className="flex flex-col gap-0.5 rounded-lg border border-border bg-background/50 px-3 py-2">
      <span className="text-lg font-semibold tabular-nums">{value}</span>
      <span className="text-[11px] text-muted-foreground">{label}</span>
    </div>
  )
}
