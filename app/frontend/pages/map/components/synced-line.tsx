import { timeAgo } from "@/lib/time"
import { accountOf } from "@/pages/map/lib/graph"
import type { MapPageProps } from "@/pages/map/types"

export function SyncedLine({ resources, connections }: Pick<MapPageProps, "resources" | "connections">) {
  const swept = connections.map((connection) => connection.sweptAt).filter((sweptAt): sweptAt is string => Boolean(sweptAt)).sort()
  const latest = swept[swept.length - 1]
  const accounts = new Set(resources.map((resource) => accountOf(resource).key)).size
  if (!latest) {
    return null
  }

  return (
    <span className="flex items-center gap-2 text-sm text-muted-foreground">
      <span className="size-1.5 rounded-full bg-success" />
      Synced {timeAgo(latest)} from {accounts} {accounts === 1 ? "account" : "accounts"}
    </span>
  )
}
