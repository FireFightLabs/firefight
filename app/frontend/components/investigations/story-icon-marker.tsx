import type { Icon } from "@tabler/icons-react"

export function StoryIconMarker({ icon: Marker }: { icon: Icon }) {
  return <Marker className="size-[13px]" strokeWidth={1.75} />
}
