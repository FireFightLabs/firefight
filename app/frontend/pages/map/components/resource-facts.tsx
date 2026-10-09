import type { ResourceMapResource } from "@/types/serializers"

export function ResourceFacts({ resource }: { resource: ResourceMapResource }) {
  if (resource.facts.length === 0) {
    return null
  }

  return (
    <dl className="grid grid-cols-2 gap-2">
      {resource.facts.map(([ label, value ]) => (
        <div key={label} className="flex flex-col gap-0.5 rounded-lg border border-border bg-background/50 px-3 py-2">
          <dt className="text-[11px] text-muted-foreground">{label}</dt>
          <dd className="truncate font-mono text-xs">{value}</dd>
        </div>
      ))}
    </dl>
  )
}
