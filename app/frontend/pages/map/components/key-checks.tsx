import { resourceMapResourceChecksPath } from "@/lib/routes"
import { CheckRow } from "@/pages/map/components/check-row"
import { useResourceJson } from "@/hooks/use-resource-json"
import type { ResourceMapCheck } from "@/types/serializers"

interface ChecksAnswer {
  checks: ResourceMapCheck[]
  none: string | null
}

// The checks worth running first on a resource, read when its panel opens, since whether each can run is worked out
// live from the connections that run or watch it.
export function KeyChecks({ resourceId }: { resourceId: string }) {
  const loaded = useResourceJson<ChecksAnswer>(resourceMapResourceChecksPath(resourceId))

  if (loaded.state === "loading") {
    return <p className="text-sm text-muted-foreground">Working out which checks can run here.</p>
  }
  if (loaded.state === "failed") {
    return <p className="text-sm text-muted-foreground">The checks could not be read. Open the resource again to retry.</p>
  }
  if (loaded.answer.none) {
    return <p className="text-sm text-muted-foreground">{loaded.answer.none}</p>
  }

  return (
    <div className="flex flex-col gap-2">
      {loaded.answer.checks.map((check) => (
        <CheckRow key={check.key} resourceId={resourceId} check={check} />
      ))}
    </div>
  )
}
