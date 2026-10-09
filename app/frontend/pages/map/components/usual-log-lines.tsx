import { resourceMapResourceLogLinesPath } from "@/lib/routes"
import { LogLine } from "@/pages/map/components/log-line"
import { useResourceJson } from "@/pages/map/hooks/use-resource-json"
import type { ResourceMapLogTemplate } from "@/types/serializers"

interface LogLinesAnswer {
  lines: ResourceMapLogTemplate[]
  total: number
  reason: string | null
}

// The kinds of line a resource printed most over the last week, read when its panel opens, so a line seen during an
// incident can be told apart from one that was always there.
export function UsualLogLines({ resourceId }: { resourceId: string }) {
  const loaded = useResourceJson<LogLinesAnswer>(resourceMapResourceLogLinesPath(resourceId))

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

function summary(shown: number, total: number): string {
  const kept = total === 1 ? "1 pattern is" : `${total} patterns are`
  return shown < total ? `${kept} known from a week of its logs. The ${shown} with the most lines are shown.` : `${kept} known from a week of its logs.`
}
