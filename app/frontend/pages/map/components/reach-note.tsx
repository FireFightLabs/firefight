import { listed } from "@/pages/map/lib/words"

// Said once someone reads the map in some environments only, so a resource they do not see reads as outside their reach.
export function ReachNote({ readsIn }: { readsIn: string[] }) {
  return (
    <span className="text-sm text-muted-foreground">
      Showing what runs in {listed(readsIn)}. An admin decides which environments you see.
    </span>
  )
}
