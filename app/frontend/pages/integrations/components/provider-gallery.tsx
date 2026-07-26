import { useMemo, useState } from "react"

import type { ProviderEntry } from "@/pages/integrations/types"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { ProviderMark } from "@/pages/integrations/components/provider-mark"

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
    <div className="flex flex-col gap-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h2 className="text-lg font-semibold">Browse integrations</h2>
          <p className="text-muted-foreground text-sm">
            Everything you connect becomes available to investigations, agents, and the API — governed
            by the same permissions and approvals.
          </p>
        </div>
        <Input
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search integrations…"
          className="max-w-56"
        />
      </div>

      {grouped.map(([category, entries]) => (
        <section key={category} className="flex flex-col gap-3">
          <div className="flex items-center gap-2">
            <h3 className="text-base font-semibold">{category}</h3>
            <Badge variant="secondary">{entries.length}</Badge>
          </div>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
            {entries.map((provider) => (
              <Card key={provider.key}>
                <CardContent className="flex h-full flex-col gap-3 p-5">
                  <div className="flex items-center gap-3">
                    <ProviderMark mark={provider.mark} color={provider.color} />
                    <span className="text-base font-semibold">{provider.name}</span>
                  </div>
                  <p className="text-muted-foreground flex-1 text-sm">{provider.description}</p>
                  <div>
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={!canManage}
                      onClick={() => onConnect(provider)}
                    >
                      Connect
                    </Button>
                  </div>
                </CardContent>
              </Card>
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
