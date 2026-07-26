import { useMemo, useState } from "react"

import type { ProviderEntry } from "@/pages/integrations/types"
import { Input } from "@/components/ui/input"
import { ProviderTile } from "@/pages/integrations/components/provider-tile"

export function ProviderGallery({
  providers,
  canManage,
  onConnect,
}: {
  providers: ProviderEntry[]
  canManage: boolean
  onConnect: (provider: ProviderEntry) => void
}) {
  const [search, setSearch] = useState("")

  const grouped = useMemo(() => {
    const matching = providers.filter((provider) =>
      `${provider.name} ${provider.category} ${provider.description}`
        .toLowerCase()
        .includes(search.toLowerCase()),
    )
    const byCategory = new Map<string, ProviderEntry[]>()
    matching.forEach((provider) => {
      byCategory.set(provider.category, [...(byCategory.get(provider.category) ?? []), provider])
    })
    return [...byCategory.entries()]
  }, [providers, search])

  return (
    <div className="flex flex-col gap-7">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="max-w-xl">
          <h2 className="text-lg font-semibold">Browse integrations</h2>
          <p className="text-muted-foreground mt-1 text-sm">
            Everything you connect becomes available to investigations, agents, and the API — governed
            by the same permissions and approvals.
          </p>
        </div>
        <Input
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search integrations…"
          className="w-56"
        />
      </div>

      {grouped.map(([category, entries]) => (
        <section key={category} className="flex flex-col gap-3">
          <div className="flex items-baseline gap-2">
            <h3 className="text-muted-foreground text-xs font-semibold tracking-wider uppercase">
              {category}
            </h3>
            <span className="text-muted-foreground/70 text-xs tabular-nums">{entries.length}</span>
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-4">
            {entries.map((provider) => (
              <ProviderTile
                key={provider.key}
                provider={provider}
                canManage={canManage}
                onConnect={onConnect}
              />
            ))}
          </div>
        </section>
      ))}

      {grouped.length === 0 && (
        <p className="text-muted-foreground py-8 text-center text-sm">No integrations match your search.</p>
      )}
    </div>
  )
}
