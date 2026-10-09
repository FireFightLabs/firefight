import type { ResourceMapEntry } from "@/types/serializers"

// What the catalog says a service is for and who owns it, so neither has to be looked up elsewhere.
export function EntryContext({ entry }: { entry: ResourceMapEntry }) {
  if (!entry.purpose && entry.owners.length === 0) {
    return null
  }

  return (
    <p className="text-sm leading-relaxed text-muted-foreground">
      <span className="font-medium text-foreground">{entry.name}</span>
      {entry.purpose && <span>: {entry.purpose}</span>}
      {entry.owners.length > 0 && <span> Owned by {entry.owners.join(", ")}.</span>}
    </p>
  )
}
