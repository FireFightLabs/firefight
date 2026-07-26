import { useMemo, useState } from "react"

import { Input } from "@/components/ui/input"
import { ProviderTile } from "@/pages/integrations/components/provider-tile"
import type { Integration } from "@/types/serializers"
import type { ProviderEntry } from "@/pages/integrations/types"

const FILTERS = ["All applications", "Connected", "Disconnected"] as const
type Filter = (typeof FILTERS)[number]

const CATEGORY_TAGLINES: Record<string, string> = {
  Code: "Correlate incidents with what shipped",
  Telemetry: "Logs, metrics and traces for investigations",
  Errors: "Error tracking tied to incidents",
  Knowledge: "Runbooks and documentation as context",
  Databases: "Read-only data checks",
  Custom: "Anything with an MCP server",
}

export function ProviderGallery({
  providers,
  integrations,
  canManage,
  onConnect,
  onDetails,
}: {
  providers: ProviderEntry[]
  integrations: Integration[]
  canManage: boolean
  onConnect: (provider: ProviderEntry) => void
  onDetails: (integration: Integration) => void
}) {
  const [search, setSearch] = useState("")
  const [filter, setFilter] = useState<Filter>("All applications")

  // The Connected/Disconnected split only means something once something is
  // connected; until then it's an empty filter, so hide the tabs entirely.
  const showFilters = integrations.length > 0
  const activeFilter = showFilters ? filter : "All applications"

  const grouped = useMemo(() => {
    const matching = providers.filter((provider) => {
      const connected = integrations.some((candidate) => candidate.provider === provider.key)
      if (activeFilter === "Connected" && !connected) return false
      if (activeFilter === "Disconnected" && connected) return false
      return `${provider.name} ${provider.category} ${provider.description}`
        .toLowerCase()
        .includes(search.toLowerCase())
    })
    const byCategory = new Map<string, ProviderEntry[]>()
    matching.forEach((provider) => {
      byCategory.set(provider.category, [...(byCategory.get(provider.category) ?? []), provider])
    })
    return [...byCategory.entries()]
  }, [providers, integrations, search, activeFilter])

  return (
    <div className="flex flex-col gap-8">
      <div className="flex flex-wrap items-center justify-between gap-4">
        {showFilters ? (
          <div className="bg-muted flex rounded-lg p-1">
            {FILTERS.map((option) => (
              <button
                key={option}
                type="button"
                onClick={() => setFilter(option)}
                className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                  activeFilter === option
                    ? "bg-background text-foreground shadow-sm"
                    : "text-muted-foreground hover:text-foreground"
                }`}
              >
                {option}
              </button>
            ))}
          </div>
        ) : (
          <div>
            <h2 className="text-lg font-semibold">Browse integrations</h2>
            <p className="text-muted-foreground text-sm">
              Everything you connect becomes available to investigations, agents, and the API.
            </p>
          </div>
        )}
        <Input
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search integrations…"
          className="w-56"
        />
      </div>

      {grouped.map(([category, entries]) => (
        <section key={category} className="flex flex-col gap-4">
          <div>
            <h3 className="text-base font-semibold">{category}</h3>
            {CATEGORY_TAGLINES[category] && (
              <p className="text-muted-foreground text-sm">{CATEGORY_TAGLINES[category]}</p>
            )}
          </div>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {entries.map((provider) => (
              <ProviderTile
                key={provider.key}
                provider={provider}
                integrations={integrations.filter((candidate) => candidate.provider === provider.key)}
                canManage={canManage}
                onConnect={onConnect}
                onDetails={onDetails}
              />
            ))}
          </div>
        </section>
      ))}

      {grouped.length === 0 && (
        <p className="text-muted-foreground py-8 text-center text-sm">No integrations match.</p>
      )}
    </div>
  )
}
