import { Link, router, usePage } from "@inertiajs/react"
import { IconExternalLink, IconX } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { SearchableSelect } from "@/components/searchable-select"
import {
  confirmResourceMapLinkPath,
  dismissResourceMapLinkPath,
  incidentPath,
  memoryPath,
  resourceMapLinkPath,
  resourceMapResourceEntriesPath,
  resourceMapResourceEntryPath,
} from "@/lib/routes"
import { CHAT_MEMORY_STATES } from "@/lib/generated/constants"
import { STATE_LABELS, STATE_TONES } from "@/pages/memory/lib/labels"
import { Clues } from "@/pages/map/components/clues"
import { changeLabel, howFound, KIND_LABELS, RELATION_SENTENCES } from "@/pages/map/lib/labels"
import { shortAgo } from "@/pages/map/lib/time"
import type { SharedProps } from "@/types"
import type {
  ResourceMapChange,
  ResourceMapEntry,
  ResourceMapLink,
  ResourceMapResource,
} from "@/types/serializers"

const VISIT = { preserveScroll: true, preserveState: true }

interface ResourcePanelProps {
  resource: ResourceMapResource
  resources: ResourceMapResource[]
  links: ResourceMapLink[]
  changes: ResourceMapChange[]
  catalogEntries: ResourceMapEntry[]
  canCurate: boolean
  onAddLink: () => void
  onPick: (resourceId: string) => void
}

export function ResourcePanel({ resource, resources, links, changes, catalogEntries, canCurate, onAddLink, onPick }: ResourcePanelProps) {
  const { agentAvailable } = usePage<SharedProps>().props
  const byId = new Map(resources.map((each) => [ each.id, each ]))
  const own = links.filter((link) => link.fromId === resource.id || link.toId === resource.id)
  const stops = resource.dependentIds.flatMap((id) => byId.get(id) ?? [])
  const maybe = resource.suggestedDependentIds.flatMap((id) => byId.get(id) ?? [])
  const recent = changes.filter((change) => change.resourceId === resource.id)
  const history = recent.length > 0 ? recent : resource.lastChange ? [ resource.lastChange ] : []

  return (
    <aside className="flex flex-col gap-6 overflow-y-auto border-t border-border bg-card/40 p-5 lg:border-t-0 lg:border-l" aria-label={`About ${resource.name}`}>
      <Section title="What it is">
        <p className="text-sm leading-relaxed">{description(resource)}</p>
        <Details resource={resource} />
        {resource.url && (
          <a href={resource.url} target="_blank" rel="noreferrer" className="flex w-fit items-center gap-1.5 text-sm text-primary hover:underline">
            Open in {resource.providerName}
            <IconExternalLink className="size-3.5" />
          </a>
        )}
      </Section>

      <Section title="Runs, from the catalog">
        <CatalogLinks resource={resource} catalogEntries={catalogEntries} canCurate={canCurate} />
      </Section>

      <Section title="Now">
        {resource.openIncidents.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {resource.catalogEntries.length === 0 ? "No catalog entry is linked, so incidents cannot reach it yet." : "No open incidents."}
          </p>
        ) : (
          resource.openIncidents.map((incident) => (
            <Link key={incident.id} href={incidentPath(incident.id)} className="flex flex-col gap-0.5 rounded-lg border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm hover:bg-destructive/15">
              <span className="font-semibold">{incident.identifier} open</span>
              <span className="text-destructive">{incident.name}</span>
            </Link>
          ))
        )}
      </Section>

      <Section title="Links and how they were found">
        {own.length === 0 && <p className="text-sm text-muted-foreground">No links yet. Nothing on the map is known to depend on it, or it on anything.</p>}
        {own.map((link) => (
          <LinkRow key={link.id} link={link} byId={byId} focusId={resource.id} canCurate={canCurate} onPick={onPick} />
        ))}
        {canCurate && (
          <div className="flex items-center gap-2 rounded-lg border border-dashed border-border px-3 py-2">
            <span className="grow text-sm text-muted-foreground">Something missing?</span>
            <Button type="button" variant="outline" size="sm" onClick={onAddLink}>
              Add link
            </Button>
          </div>
        )}
      </Section>

      <Section title="If it fails">
        <p className="text-sm leading-relaxed">{failureSentence(stops)}</p>
        {maybe.length > 0 && (
          <p className="text-sm leading-relaxed text-muted-foreground">
            If the suggested links are right, {names(maybe)} {maybe.length === 1 ? "stops" : "stop"} too.
          </p>
        )}
      </Section>

      {agentAvailable && (
        <Section title="Halon remembers">
          <Remembered resource={resource} />
        </Section>
      )}

      <Section title="Recent changes">
        {history.length === 0 && <p className="text-sm text-muted-foreground">No changes seen since it was first swept.</p>}
        {history.map((change) => (
          <div key={change.id} className="flex justify-between gap-3 text-sm">
            <span>{changeLabel(change)}</span>
            <span className="shrink-0 text-muted-foreground tabular-nums">{shortAgo(change.happenedAt)}</span>
          </div>
        ))}
      </Section>
    </aside>
  )
}

function failureSentence(stops: ResourceMapResource[]): string {
  if (stops.length === 0) {
    return "Nothing on the map is known to depend on it, so a failure reaches only its own users."
  }
  const count = stops.length === 1 ? "1 resource depends" : `${stops.length} resources depend`
  return `${count} on it, directly or through others: ${names(stops)}.`
}

function names(resources: ResourceMapResource[]): string {
  return resources.map((each) => each.name).join(", ")
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-2.5">
      <h2 className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">{title}</h2>
      {children}
    </section>
  )
}

function description(resource: ResourceMapResource): string {
  const where = [ resource.providerName, resource.account ].join(" ")
  const environment = resource.environment ? `, ${resource.environment}` : ""
  const status = resource.status ? ` Last seen ${resource.status}.` : ""
  return `${KIND_LABELS[resource.kind]} in ${where}${environment}.${status}`
}

function Details({ resource }: { resource: ResourceMapResource }) {
  if (resource.facts.length === 0) {
    return null
  }

  return (
    <dl className="grid grid-cols-2 gap-2">
      {resource.facts.map(([ label, value ]) => (
        <div key={label} className="flex flex-col gap-0.5 rounded-lg border border-border bg-background/50 px-3 py-2">
          <dt className="text-[11px] text-muted-foreground">{label}</dt>
          <dd className="truncate font-mono text-xs">{value}</dd>
        </div>
      ))}
    </dl>
  )
}

interface CatalogLinksProps {
  resource: ResourceMapResource
  catalogEntries: ResourceMapEntry[]
  canCurate: boolean
}

function CatalogLinks({ resource, catalogEntries, canCurate }: CatalogLinksProps) {
  const linked = new Set(resource.catalogEntries.map((entry) => entry.id))
  const options = catalogEntries.filter((entry) => !linked.has(entry.id)).map((entry) => ({ value: entry.id, label: `${entry.name} · ${entry.typeName}` }))

  function linkEntry(entryId: string | null) {
    if (entryId) {
      router.post(resourceMapResourceEntriesPath(resource.id), { catalog_entry_id: entryId }, VISIT)
    }
  }

  return (
    <div className="flex flex-col gap-2">
      {resource.catalogEntries.length === 0 && (
        <p className="text-sm text-muted-foreground">Not linked yet. Link the catalog entry it runs, so its owner and its incidents show here.</p>
      )}
      <div className="flex flex-wrap gap-2">
        {resource.catalogEntries.map((entry) => (
          <EntryChip key={entry.id} resourceId={resource.id} entry={entry} canCurate={canCurate} />
        ))}
      </div>
      {canCurate && options.length > 0 && (
        <SearchableSelect
          value={null}
          onValueChange={linkEntry}
          options={options}
          placeholder="Link a catalog entry"
          searchPlaceholder="Search the catalog"
          emptyText="No catalog entry matches"
        />
      )}
    </div>
  )
}

function EntryChip({ resourceId, entry, canCurate }: { resourceId: string; entry: ResourceMapEntry; canCurate: boolean }) {
  function unlink() {
    router.delete(resourceMapResourceEntryPath(resourceId, entry.id), VISIT)
  }

  return (
    <span className="flex items-center gap-1.5 rounded-md border border-border bg-background/60 py-1 pr-1 pl-2.5 text-sm">
      <span>{entry.name}</span>
      <span className="text-xs text-muted-foreground">{entry.typeName}</span>
      {canCurate && (
        <button type="button" onClick={unlink} aria-label={`Unlink ${entry.name}`} className="rounded p-0.5 text-muted-foreground hover:bg-muted hover:text-foreground">
          <IconX className="size-3.5" />
        </button>
      )}
    </span>
  )
}

interface LinkRowProps {
  link: ResourceMapLink
  byId: Map<string, ResourceMapResource>
  focusId: string
  canCurate: boolean
  onPick: (resourceId: string) => void
}

function LinkRow({ link, byId, focusId, canCurate, onPick }: LinkRowProps) {
  const from = byId.get(link.fromId)
  const to = byId.get(link.toId)
  const other = link.fromId === focusId ? to : from

  function confirm() {
    router.post(confirmResourceMapLinkPath(link.id), {}, VISIT)
  }

  function dismiss() {
    router.post(dismissResourceMapLinkPath(link.id), {}, VISIT)
  }

  function remove() {
    router.delete(resourceMapLinkPath(link.id), VISIT)
  }

  function pickOther() {
    if (other) {
      onPick(other.id)
    }
  }

  return (
    <div className={`flex flex-col gap-1.5 rounded-lg border px-3 py-2.5 text-sm ${link.unconfirmed ? "border-dashed border-primary/50 bg-primary/5" : "border-border bg-background/50"}`}>
      <span>
        <b className="font-semibold">{from?.name}</b> {RELATION_SENTENCES[link.relation]}{" "}
        <button type="button" onClick={pickOther} className="font-semibold hover:underline">
          {to?.name}
        </button>
      </span>
      <span className="text-xs text-muted-foreground">{howFound(link)}{link.note ? `: ${link.note}` : ""}</span>
      {link.unconfirmed && link.clues.length > 0 && <Clues clues={link.clues} />}
      {canCurate && link.unconfirmed && (
        <div className="flex gap-2 pt-1">
          <Button type="button" size="sm" onClick={confirm}>
            Confirm link
          </Button>
          <Button type="button" size="sm" variant="outline" onClick={dismiss}>
            Dismiss
          </Button>
        </div>
      )}
      {canCurate && !link.unconfirmed && <RemoveLink reason={link.removalBlockedReason} onRemove={remove} />}
    </div>
  )
}

// A provider's link cannot be removed by hand, so the control stays and says why.
function RemoveLink({ reason, onRemove }: { reason?: string; onRemove: () => void }) {
  const button = (
    <Button type="button" size="sm" variant="ghost" className="h-7 w-fit px-2 text-xs text-muted-foreground" disabled={Boolean(reason)} onClick={onRemove}>
      Remove link
    </Button>
  )
  if (!reason) {
    return button
  }

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span className="w-fit">{button}</span>
      </TooltipTrigger>
      <TooltipContent>{reason}</TooltipContent>
    </Tooltip>
  )
}

// What Halon knows about this resource and how it was told to work on it, both written on the Memory page.
function Remembered({ resource }: { resource: ResourceMapResource }) {
  if (resource.memories.length === 0 && resource.instructions.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        Nothing yet. Halon learns about it from incidents, or you can{" "}
        <Link href={memoryPath()} className="text-primary hover:underline">
          add memories and instructions
        </Link>
        .
      </p>
    )
  }

  return (
    <div className="flex flex-col gap-2">
      {resource.instructions.map(([ label, text ]) => (
        <div key={label} className="flex flex-col gap-1 rounded-lg border border-border bg-background/50 px-3 py-2">
          <span className="text-[11px] text-muted-foreground">Instructions for {label}</span>
          <p className="line-clamp-4 text-sm whitespace-pre-wrap">{text}</p>
        </div>
      ))}
      {resource.memories.map(([ id, state, text ]) => (
        <MemoryNote key={id} state={state} text={text} />
      ))}
      <Link href={memoryPath()} className="w-fit text-sm text-primary hover:underline">
        Review on the Memory page
      </Link>
    </div>
  )
}

function MemoryNote({ state, text }: { state: string; text: string }) {
  const known = CHAT_MEMORY_STATES.find((each) => each === state)

  return (
    <div className="flex flex-col items-start gap-1.5 rounded-lg border border-border bg-background/50 px-3 py-2">
      {known && <span className={`rounded-full border px-2 py-0.5 text-[11px] font-medium ${STATE_TONES[known]}`}>{STATE_LABELS[known]}</span>}
      <p className="text-sm">{text}</p>
    </div>
  )
}
