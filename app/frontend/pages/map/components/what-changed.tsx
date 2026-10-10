import { IconExternalLink } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import type { ResourceMapTimelineSource } from "@/lib/generated/constants"
import { resourceMapResourceChangesPath } from "@/lib/routes"
import { shortAgo } from "@/lib/time"
import { useResourceJson } from "@/pages/map/hooks/use-resource-json"
import { changeLabel } from "@/pages/map/lib/labels"
import type { ResourceMapChange, ResourceMapTimelineEntry } from "@/types/serializers"

interface ChangesAnswer {
  entries: ResourceMapTimelineEntry[]
  notes: string[]
  readsRuns: boolean
  readLive: boolean
}

const SOURCE_TONES: Record<ResourceMapTimelineSource, string> = {
  map: "border-border text-muted-foreground",
  live_update: "border-warning/40 bg-warning-tint text-warning",
  provider: "border-primary/30 bg-primary/10 text-primary",
  firefight: "border-border bg-muted text-foreground",
}

// What changed around a resource over the last week, read when its panel opens from what Firefight holds. Reading its
// runs asks the provider that runs it, as the person, so it waits for the button.
export function WhatChanged({ resourceId, lastChange }: { resourceId: string; lastChange?: ResourceMapChange }) {
  const [ reads, setReads ] = useState(0)
  const path = reads > 0 ? resourceMapResourceChangesPath(resourceId, { live: reads }) : resourceMapResourceChangesPath(resourceId)
  const loaded = useResourceJson<ChangesAnswer>(path)

  function readRuns() {
    setReads(reads + 1)
  }

  if (loaded.state === "loading") {
    return <p className="text-sm text-muted-foreground">{reads > 0 ? "Reading its runs from the provider." : "Reading what changed."}</p>
  }
  if (loaded.state === "failed") {
    return <p className="text-sm text-muted-foreground">What changed could not be read. Open the resource again to retry.</p>
  }
  const { entries, notes, readsRuns, readLive } = loaded.answer

  return (
    <div className="flex flex-col gap-2">
      {entries.length === 0 && <p className="text-sm text-muted-foreground">{nothingSentence(lastChange)}</p>}
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
            {readLive ? "Its runs were read just now." : "Its deploys and runs are the ones the map saw."}
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

function nothingSentence(lastChange?: ResourceMapChange): string {
  if (!lastChange) {
    return "Nothing Firefight holds changed in the last week."
  }
  return `Nothing Firefight holds changed in the last week. The last change seen was ${changeLabel(lastChange)}, ${shortAgo(lastChange.happenedAt)} ago.`
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
