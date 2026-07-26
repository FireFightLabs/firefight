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

  const grouped = useMemo(() => {
    const matching = providers.filter((provider) => {
      const integration = integrations.find((candidate) => candidate.provider === provider.key) ?? null
      if (filter === "Connected" && integration === null) return false
      if (filter === "Disconnected" && integration !== null) return false
      return `${provider.name} ${provider.category} ${provider.description}`
        .toLowerCase()
        .includes(search.toLowerCase())
    })
    const byCategory = new Map<string, ProviderEntry[]>()
    matching.forEach((provider) => {
      byCategory.set(provider.category, [...(byCategory.get(provider.category) ?? []), provider])
    })
    return [...byCategory.entries()]
  }, [providers, integrations, search, filter])

  return (
    <div className="flex flex-col gap-8">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div className="bg-muted flex rounded-lg p-1">
          {FILTERS.map((option) => (
            <button
              key={option}
              type="button"
              onClick={() => setFilter(option)}
              className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                filter === option
                  ? "bg-background text-foreground shadow-sm"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              {option}
            </button>
          ))}
        </div>
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
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
            {entries.map((provider) => (
              <ProviderTile
                key={provider.key}
                provider={provider}
                integration={integrations.find((candidate) => candidate.provider === provider.key) ?? null}
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
