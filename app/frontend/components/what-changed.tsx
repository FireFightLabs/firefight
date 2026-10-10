import { IconExternalLink } from "@tabler/icons-react"
import { type ReactNode, useState } from "react"

import { Button } from "@/components/ui/button"
import { useResourceJson } from "@/hooks/use-resource-json"
import type { ResourceMapTimelineSource } from "@/lib/generated/constants"
import { shortAgo } from "@/lib/time"
import type { ResourceMapTimelineEntry } from "@/types/serializers"

interface ChangesAnswer {
  entries: ResourceMapTimelineEntry[]
  notes: string[]
  readsRuns: boolean
  readLive: boolean
}

interface WhatChangedProps {
  // The answer's address, with how many times runs were asked for, 0 until the button is pressed.
  pathFor: (reads: number) => string
  // What a list with nothing in it says.
  quiet: string
  // A line shown above the list, such as the last change the map saw.
  glance?: ReactNode
}

const SOURCE_TONES: Record<ResourceMapTimelineSource, string> = {
  map: "border-border text-muted-foreground",
  live_update: "border-warning/40 bg-warning-tint text-warning",
  provider: "border-primary/30 bg-primary/10 text-primary",
  firefight: "border-border bg-muted text-foreground",
}

// What changed, read from what Firefight holds when it opens. Reading runs asks the provider that runs each resource, as
// the person, so it waits for the button.
export function WhatChanged({ pathFor, quiet, glance }: WhatChangedProps) {
  const [ reads, setReads ] = useState(0)
  const loaded = useResourceJson<ChangesAnswer>(pathFor(reads))

  function readRuns() {
    setReads(reads + 1)
  }

  if (loaded.state === "loading") {
    return <p className="text-sm text-muted-foreground">{reads > 0 ? "Reading runs from the provider." : "Reading what changed."}</p>
  }
  if (loaded.state === "failed") {
    return <p className="text-sm text-muted-foreground">What changed could not be read. Open it again to retry.</p>
  }
  const { entries, notes, readsRuns, readLive } = loaded.answer

  return (
    <div className="flex flex-col gap-2">
      {entries.length === 0 && <p className="text-sm text-muted-foreground">{quiet}</p>}
      {entries.length > 0 && glance}
      {entries.length > 0 && (
        <ul className="flex flex-col gap-1.5">
          {entries.map((entry) => (
            <ChangeRow key={entry.id} entry={entry} />
          ))}
        </ul>
      )}
      {readsRuns && (
        <div className="flex items-center gap-2 rounded-lg border border-dashed border-border px-3 py-2">
          <span className="grow text-sm text-muted-foreground">
            {readLive ? "Runs were read just now." : "Deploys and runs here are the ones the map saw."}
          </span>
          <Button type="button" variant="outline" size="sm" onClick={readRuns}>
            {readLive ? "Read again" : "Read runs now"}
          </Button>
        </div>
      )}
      {notes.length > 0 && (
        <ul className="flex flex-col gap-1 text-xs text-muted-foreground">
          {notes.map((note) => (
            <li key={note}>{note}</li>
          ))}
        </ul>
      )}
    </div>
  )
}

function ChangeRow({ entry }: { entry: ResourceMapTimelineEntry }) {
  return (
    <li className="flex flex-col gap-1 rounded-lg border border-border bg-background/50 px-3 py-2">
      <span className="text-sm leading-snug break-words">{entry.what}</span>
      <span className="flex flex-wrap items-center gap-2 text-[11px] text-muted-foreground">
        <span className={`rounded-full border px-1.5 py-px font-medium ${SOURCE_TONES[entry.source]}`}>{entry.label}</span>
        {entry.by && <span>by {entry.by}</span>}
        <span className="tabular-nums">{shortAgo(entry.at)} ago</span>
        {entry.link && (
          <a href={entry.link} target="_blank" rel="noreferrer" className="flex items-center gap-1 text-link hover:underline">
            Open
            <IconExternalLink className="size-3" />
          </a>
        )}
      </span>
    </li>
  )
}
