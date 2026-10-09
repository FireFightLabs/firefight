import { Link } from "@inertiajs/react"

import { memoryPath } from "@/lib/routes"
import { MemoryNote } from "@/pages/map/components/memory-note"
import type { ResourceMapResource } from "@/types/serializers"

// What Halon knows about this resource and how it was told to work on it, both written on the Memory page.
export function Remembered({ resource }: { resource: ResourceMapResource }) {
  if (resource.memories.length === 0 && resource.instructions.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        Nothing yet. Halon learns about it from incidents, or you can{" "}
        <Link href={memoryPath()} className="text-link hover:underline">
          add memories and instructions
        </Link>
        .
      </p>
    )
  }

  return (
    <div className="flex flex-col gap-2">
      {resource.instructions.map(([ id, label, text ]) => (
        <div key={id} className="flex flex-col gap-1 rounded-lg border border-border bg-background/50 px-3 py-2">
          <span className="text-[11px] text-muted-foreground">Instructions for {label}</span>
          <p className="line-clamp-4 text-sm whitespace-pre-wrap">{text}</p>
        </div>
      ))}
      {resource.memories.map(([ id, state, text ]) => (
        <MemoryNote key={id} state={state} text={text} />
      ))}
      <Link href={memoryPath()} className="w-fit text-sm text-link hover:underline">
        Review on the Memory page
      </Link>
    </div>
  )
}
