import type { ChangeEvent } from "react"
import { IconSearch } from "@tabler/icons-react"

import { Input } from "@/components/ui/input"
import { RESOURCE_MAP_KINDS } from "@/lib/generated/constants"
import { KIND_LABELS } from "@/lib/resource-map-kinds"
import { ALL, FilterSelect } from "@/pages/map/components/filter-select"
import type { MapFilters } from "@/pages/map/types"
import type { ResourceMapResource } from "@/types/serializers"

interface FiltersBarProps {
  resources: ResourceMapResource[]
  filters: MapFilters
  onChange: (filters: MapFilters) => void
}

function unique(values: (string | undefined)[]): string[] {
  return [ ...new Set(values.filter((value): value is string => Boolean(value))) ].sort()
}

export function FiltersBar({ resources, filters, onChange }: FiltersBarProps) {
  const environments = unique(resources.map((resource) => resource.environment))
  const providers = unique(resources.map((resource) => resource.provider))
  const providerNames = new Map(resources.map((resource) => [ resource.provider, resource.providerName ]))
  const kinds = RESOURCE_MAP_KINDS.filter((kind) => resources.some((resource) => resource.kind === kind))

  function search(event: ChangeEvent<HTMLInputElement>) {
    onChange({ ...filters, query: event.target.value })
  }

  function environment(value: string) {
    onChange({ ...filters, environment: value === ALL ? null : value })
  }

  function provider(value: string) {
    onChange({ ...filters, provider: value === ALL ? null : value })
  }

  function kind(value: string) {
    onChange({ ...filters, kind: kinds.find((each) => each === value) ?? null })
  }

  return (
    <>
      <div className="relative w-full sm:w-72">
        <IconSearch className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
        <label htmlFor="map-search" className="sr-only">Search resources</label>
        <Input id="map-search" type="search" placeholder="Search resources, repositories, domains" value={filters.query} onChange={search} className="h-8 pl-8" />
      </div>
      {environments.length > 0 && (
        <FilterSelect label="Environment" value={filters.environment} onChange={environment} options={environments.map((each) => [ each, each ])} />
      )}
      {providers.length > 1 && (
        <FilterSelect label="Provider" value={filters.provider} onChange={provider} options={providers.map((each) => [ each, providerNames.get(each) ?? each ])} />
      )}
      {kinds.length > 1 && <FilterSelect label="Type" value={filters.kind} onChange={kind} options={kinds.map((each) => [ each, KIND_LABELS[each] ])} />}
    </>
  )
}
