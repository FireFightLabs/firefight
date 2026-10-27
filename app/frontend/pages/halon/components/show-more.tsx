import type { InfiniteScrollActionSlotProps } from "@inertiajs/core"
import { IconLoader2 } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"

// The next page of a list comes on a click, so whatever sits below a long list stays reachable.
export function ShowMore({ loading, hasMore, fetch }: InfiniteScrollActionSlotProps) {
  if (!hasMore) {
    return null
  }
  return (
    <div className="flex justify-center border-t border-border px-5 py-3">
      <Button variant="ghost" size="sm" onClick={fetch} disabled={loading}>
        {loading && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
        {loading ? "Loading more" : "Show more"}
      </Button>
    </div>
  )
}
