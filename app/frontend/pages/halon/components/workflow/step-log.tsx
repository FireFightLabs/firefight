import { useState } from "react"

import { Button } from "@/components/ui/button"
import { WORKFLOW_RUN_LOG_TONES } from "@/lib/generated/constants"
import { cn } from "@/lib/utils"
import { clockLabel } from "@/pages/halon/lib/workflow/run-states"
import type { WorkflowRunStep } from "@/types/serializers"

type LogEntry = WorkflowRunStep["log"][number]

// The newest lines show at once, the earlier ones a click away, so a watch that read for an hour stays readable.
const SHOWN_AT_FIRST = 30

const TONE_MARKS: Record<LogEntry["tone"], string> = {
  [WORKFLOW_RUN_LOG_TONES.NEUTRAL]: "bg-fg-muted",
  [WORKFLOW_RUN_LOG_TONES.GOOD]: "bg-success",
  [WORKFLOW_RUN_LOG_TONES.BAD]: "bg-error",
  [WORKFLOW_RUN_LOG_TONES.WAITING]: "bg-warning",
}

interface StepLogProps {
  entries: LogEntry[]
  // The step is still going, so the log is still being written.
  going: boolean
}

// Everything one step did, oldest first and the newest at the foot: when it started, each call it made through the
// gateway and how it ended, each tool Halon called for it, what a watch it keeps said and saw, and how it ended. The
// same call made again and again in a row reads as one line with how many times and from when to when.
export function StepLog({ entries, going }: StepLogProps) {
  const [ showAll, setShowAll ] = useState(false)
  const hidden = showAll ? 0 : Math.max(entries.length - SHOWN_AT_FIRST, 0)
  const shown = entries.slice(hidden)

  function revealEarlier() {
    setShowAll(true)
  }

  return (
    <section className="space-y-1.5" aria-label="What it did">
      <h5 className="text-[11px] font-medium text-fg-secondary">What it did</h5>
      {entries.length === 0 ? (
        <p className="text-xs text-fg-muted">{going ? "Nothing yet. Lines show here as it works." : "Nothing was recorded for this step."}</p>
      ) : (
        <>
          {hidden > 0 && (
            <Button type="button" variant="ghost" size="sm" className="h-7 px-2 text-xs" onClick={revealEarlier}>
              Show {hidden} earlier {hidden === 1 ? "line" : "lines"}
            </Button>
          )}
          <ol className="space-y-2">
            {shown.map((entry) => (
              <li key={entry.id} className="flex gap-2 text-xs">
                <span aria-hidden className={cn("mt-1.5 size-1.5 shrink-0 rounded-full", TONE_MARKS[entry.tone])} />
                <div className="min-w-0 flex-1 space-y-0.5">
                  <div className="flex items-baseline justify-between gap-2">
                    <p className="min-w-0 text-fg-primary [overflow-wrap:anywhere]">
                      {entry.text}
                      {entry.count > 1 && <span className="text-fg-muted"> ({entry.count} times)</span>}
                    </p>
                    <time dateTime={entry.at} className="shrink-0 font-mono text-[11px] text-fg-muted tabular-nums">
                      {clockLabel(entry.at)}
                      {entry.until && ` to ${clockLabel(entry.until)}`}
                    </time>
                  </div>
                  {entry.detail && (
                    <p className="max-h-40 overflow-auto whitespace-pre-wrap text-fg-secondary [overflow-wrap:anywhere]">{entry.detail}</p>
                  )}
                </div>
              </li>
            ))}
          </ol>
        </>
      )}
    </section>
  )
}
