import { router } from "@inertiajs/react"

import { SearchableSelect } from "@/components/searchable-select"
import { resourceMapResourceEntriesPath } from "@/lib/routes"
import { EntryChip } from "@/pages/map/components/entry-chip"
import { EntryContext } from "@/pages/map/components/entry-context"
import { MAP_VISIT } from "@/pages/map/lib/visit"
import type { ResourceMapEntry, ResourceMapResource } from "@/types/serializers"

interface CatalogLinksProps {
  resource: ResourceMapResource
  catalogEntries: ResourceMapEntry[]
  canCurate: boolean
}

export function CatalogLinks({ resource, catalogEntries, canCurate }: CatalogLinksProps) {
  const linked = new Set(resource.catalogEntries.map((entry) => entry.id))
  const options = catalogEntries.filter((entry) => !linked.has(entry.id)).map((entry) => ({ value: entry.id, label: `${entry.name} · ${entry.typeName}` }))

  function linkEntry(entryId: string | null) {
    if (entryId) {
      router.post(resourceMapResourceEntriesPath(resource.id), { catalog_entry_id: entryId }, MAP_VISIT)
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
      {resource.catalogEntries.map((entry) => (
        <EntryContext key={entry.id} entry={entry} />
      ))}
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
