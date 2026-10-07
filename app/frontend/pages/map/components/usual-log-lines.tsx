import { useEffect, useState } from "react"

import { requestJson } from "@/lib/http"
import { resourceMapResourceLogLinesPath } from "@/lib/routes"
import type { ResourceMapLogLevel } from "@/lib/generated/constants"
import type { ResourceMapLogTemplate } from "@/types/serializers"

interface LogLinesAnswer {
  lines: ResourceMapLogTemplate[]
  total: number
  reason: string | null
}

type Loaded = { state: "loading" } | { state: "failed" } | { state: "loaded"; answer: LogLinesAnswer }

const LEVEL_TONES: Record<ResourceMapLogLevel, string> = {
  error: "border-destructive/40 bg-destructive/10 text-destructive",
  warning: "border-warning/40 bg-warning-tint text-warning",
}

// The kinds of line a resource printed most over the last week, read when its panel opens, so a line seen during an
// incident can be told apart from one that was always there.
export function UsualLogLines({ resourceId }: { resourceId: string }) {
  const [ loaded, setLoaded ] = useState<Loaded>({ state: "loading" })

  useEffect(() => {
    const controller = new AbortController()
    setLoaded({ state: "loading" })
    requestJson<LogLinesAnswer>(resourceMapResourceLogLinesPath(resourceId), { method: "GET", signal: controller.signal })
      .then(({ ok, data }) => {
        setLoaded(ok && data ? { state: "loaded", answer: data } : { state: "failed" })
      })
      .catch(() => {
        if (!controller.signal.aborted) {
          setLoaded({ state: "failed" })
        }
      })
    return () => {
      controller.abort()
    }
  }, [ resourceId ])

  if (loaded.state === "loading") {
    return <p className="text-sm text-muted-foreground">Reading what it usually logs.</p>
  }
  if (loaded.state === "failed") {
    return <p className="text-sm text-muted-foreground">The usual log lines could not be read. Open the resource again to retry.</p>
  }
  const { lines, total, reason } = loaded.answer
  if (lines.length === 0) {
    return <p className="text-sm text-muted-foreground">{reason}</p>
  }

  return (
    <div className="flex flex-col gap-1.5">
      <ul className="flex flex-col gap-1.5">
        {lines.map((line) => (
          <LogLine key={line.id} line={line} />
        ))}
      </ul>
      <p className="text-xs text-muted-foreground">{summary(lines.length, total)}</p>
    </div>
  )
}

function LogLine({ line }: { line: ResourceMapLogTemplate }) {
  return (
    <li className="flex flex-col gap-1 rounded-lg border border-border bg-background/50 px-3 py-2">
      <code className="font-mono text-[11.5px] leading-relaxed break-words">{line.template}</code>
      <span className="flex items-center gap-2 text-[11px] text-muted-foreground">
        {line.level && <span className={`rounded-full border px-1.5 py-px font-medium ${LEVEL_TONES[line.level]}`}>{line.level}</span>}
        <span>
          {line.lines} {line.lines === 1 ? "line" : "lines"} in the last read, seen in {line.samples} {line.samples === 1 ? "read" : "reads"}
        </span>
      </span>
    </li>
  )
}

function summary(shown: number, total: number): string {
  const kept = total === 1 ? "1 pattern is" : `${total} patterns are`
  return shown < total ? `${kept} known from a week of its logs. The ${shown} with the most lines are shown.` : `${kept} known from a week of its logs.`
}
