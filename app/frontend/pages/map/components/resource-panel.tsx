import { Link, usePage } from "@inertiajs/react"
import { IconExternalLink } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { PAST_INCIDENT_DAYS } from "@/lib/generated/constants"
import { incidentPath } from "@/lib/routes"
import { KIND_LABELS } from "@/lib/resource-map-kinds"
import { BaselinesTable } from "@/pages/map/components/baselines-table"
import { CatalogLinks } from "@/pages/map/components/catalog-links"
import { KeyChecks } from "@/pages/map/components/key-checks"
import { LinkRow } from "@/pages/map/components/link-row"
import { PanelSection } from "@/pages/map/components/panel-section"
import { PastIncidentRow } from "@/pages/map/components/past-incident-row"
import { PointingSettings } from "@/pages/map/components/pointing-settings"
import { Remembered } from "@/pages/map/components/remembered"
import { ResourceFacts } from "@/pages/map/components/resource-facts"
import { UsualLogLines } from "@/pages/map/components/usual-log-lines"
import { WhatChanged } from "@/pages/map/components/what-changed"
import { settingsPointingAt } from "@/pages/map/lib/pointing"
import type { SharedProps } from "@/types"
import type { ResourceMapEntry, ResourceMapLink, ResourceMapResource } from "@/types/serializers"

interface ResourcePanelProps {
  resource: ResourceMapResource
  resources: ResourceMapResource[]
  links: ResourceMapLink[]
  catalogEntries: ResourceMapEntry[]
  canCurate: boolean
  onAddLink: () => void
  onPick: (resourceId: string) => void
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

function description(resource: ResourceMapResource): string {
  const where = [ resource.providerName, resource.account ].join(" ")
  const environment = resource.environment ? `, ${resource.environment}` : ""
  const status = resource.status ? ` Last seen ${resource.status}.` : ""
  return `${KIND_LABELS[resource.kind]} in ${where}${environment}.${status}`
}

export function ResourcePanel({ resource, resources, links, catalogEntries, canCurate, onAddLink, onPick }: ResourcePanelProps) {
  const { agentAvailable } = usePage<SharedProps>().props
  const byId = new Map(resources.map((each) => [ each.id, each ]))
  const own = links.filter((link) => link.fromId === resource.id || link.toId === resource.id)
  const stops = resource.dependentIds.flatMap((id) => byId.get(id) ?? [])
  const maybe = resource.suggestedDependentIds.flatMap((id) => byId.get(id) ?? [])
  const pointing = settingsPointingAt(resource, own, byId)

  return (
    <aside className="flex flex-col gap-6 overflow-y-auto border-t border-border bg-card/40 p-5 lg:border-t-0 lg:border-l" aria-label={`About ${resource.name}`}>
      <PanelSection title="What it is">
        <p className="text-sm leading-relaxed">{description(resource)}</p>
        <ResourceFacts resource={resource} />
        {resource.url && (
          <a href={resource.url} target="_blank" rel="noreferrer" className="flex w-fit items-center gap-1.5 text-sm text-link hover:underline">
            Open in {resource.providerName}
            <IconExternalLink className="size-3.5" />
          </a>
        )}
      </PanelSection>

      <PanelSection title="Runs, from the catalog">
        <CatalogLinks resource={resource} catalogEntries={catalogEntries} canCurate={canCurate} />
      </PanelSection>

      <PanelSection title="Now">
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
      </PanelSection>

      <PanelSection title="Key checks">
        <KeyChecks resourceId={resource.id} />
      </PanelSection>

      <PanelSection title="Past incidents">
        {resource.pastIncidents.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {resource.catalogEntries.length === 0 ? "No catalog entry is linked, so its incidents cannot be found yet." : `No incidents ended on it in the last ${PAST_INCIDENT_DAYS} days.`}
          </p>
        ) : (
          resource.pastIncidents.map((incident) => <PastIncidentRow key={incident.id} incident={incident} />)
        )}
      </PanelSection>
      {resource.baselines.length > 0 && (
        <PanelSection title="Normal, over the last week">
          <BaselinesTable baselines={resource.baselines} />
        </PanelSection>
      )}

      <PanelSection title="Usual log lines">
        <UsualLogLines resourceId={resource.id} />
      </PanelSection>

      {pointing.length > 0 && (
        <PanelSection title="Settings that point here">
          <PointingSettings settings={pointing} onPick={onPick} />
        </PanelSection>
      )}

      <PanelSection title="Links and how they were found">
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
      </PanelSection>

      <PanelSection title="If it fails">
        <p className="text-sm leading-relaxed">{failureSentence(stops)}</p>
        {maybe.length > 0 && (
          <p className="text-sm leading-relaxed text-muted-foreground">
            If the suggested links are right, {names(maybe)} {maybe.length === 1 ? "stops" : "stop"} too.
          </p>
        )}
      </PanelSection>

      {agentAvailable && (
        <PanelSection title="Halon remembers">
          <Remembered resource={resource} />
        </PanelSection>
      )}

      <PanelSection title="What changed">
        <WhatChanged key={resource.id} resourceId={resource.id} lastChange={resource.lastChange} />
      </PanelSection>
    </aside>
  )
}
