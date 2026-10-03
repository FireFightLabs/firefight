import { useMemo, useState } from "react"

import { Input } from "@/components/ui/input"
import { ProviderAbout } from "@/pages/integrations/components/provider-about"
import { ProviderTile } from "@/pages/integrations/components/provider-tile"
import type { Integration } from "@/types/serializers"
import type { IntegrationProvider } from "@/types/serializers"

const FILTERS = ["All applications", "Connected", "Disconnected"] as const
type Filter = (typeof FILTERS)[number]

export function ProviderGallery({
  providers,
  categories,
  integrations,
  canManage,
  onConnect,
  onDetails,
}: {
  providers: IntegrationProvider[]
  categories: Record<string, string>
  integrations: Integration[]
  canManage: boolean
  onConnect: (provider: IntegrationProvider) => void
  onDetails: (integration: Integration) => void
}) {
  const [search, setSearch] = useState("")
  const [filter, setFilter] = useState<Filter>("All applications")
  const [about, setAbout] = useState<IntegrationProvider | null>(null)

  function closeAbout() {
    setAbout(null)
  }

  // The Connected/Disconnected split means nothing until something is connected.
  const showFilters = integrations.length > 0
  const activeFilter = showFilters ? filter : "All applications"

  const grouped = useMemo(() => {
    const matching = providers.filter((provider) => {
      const connected = integrations.some((candidate) => candidate.provider === provider.key)
      if (activeFilter === "Connected" && !connected) {
        return false
      }
      if (activeFilter === "Disconnected" && connected) {
        return false
      }
      return `${provider.name} ${provider.category} ${provider.description}`
        .toLowerCase()
        .includes(search.toLowerCase())
    })
    const byCategory = new Map<string, IntegrationProvider[]>()
    matching.forEach((provider) => {
      byCategory.set(provider.category, [...(byCategory.get(provider.category) ?? []), provider])
    })
    // In the registry's order, so the groups read the same every time.
    const order = Object.keys(categories)
    const rank = (category: string) => (order.includes(category) ? order.indexOf(category) : order.length)
    return [...byCategory.entries()].sort(([first], [second]) => rank(first) - rank(second))
  }, [providers, integrations, search, activeFilter, categories])

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
                    ? "bg-surface-selected text-fg-primary ring-1 ring-border-strong"
                    : "text-fg-secondary hover:text-fg-primary"
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
            {categories[category] && (
              <p className="text-muted-foreground text-sm">{categories[category]}</p>
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
                onAbout={setAbout}
              />
            ))}
          </div>
        </section>
      ))}

      {grouped.length === 0 && (
        <p className="text-muted-foreground py-8 text-center text-sm">No integrations match.</p>
      )}

      <ProviderAbout provider={about} onClose={closeAbout} />
    </div>
  )
}
