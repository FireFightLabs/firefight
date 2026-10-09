import { formatDateTime } from "@/lib/formatters"
import { TraceSpanRow } from "@/pages/operator/components/trace-span-row"
import type { OperatorTraceGroup } from "@/types/serializers"

const TICKS = 6

function timeAxis(group: OperatorTraceGroup) {
  const start = new Date(group.startedAt ?? 0).getTime()
  const end = new Date(group.endedAt ?? group.startedAt ?? 0).getTime()
  return { start, total: Math.max(end - start, 1) }
}

// Formats a tick. Under a second in ms, under ten seconds in tenths, longer ones as m:ss or h:mm:ss.
function tickLabel(milliseconds: number, span: number): string {
  if (span < 1000) {
    return `${Math.round(milliseconds)}ms`
  }
  if (span < 10_000) {
    return `${(milliseconds / 1000).toFixed(1)}s`
  }
  const total = Math.round(milliseconds / 1000)
  if (total < 60) {
    return `${total}s`
  }
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const secondsLeft = String(total % 60).padStart(2, "0")
  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${secondsLeft}` : `${minutes}:${secondsLeft}`
}

// Keeps the first and last tick labels inside the ruler.
function tickAlign(index: number): string {
  if (index === 0) {
    return ""
  }
  return index === TICKS - 1 ? "-translate-x-full" : "-translate-x-1/2"
}

export function TraceGroup({ group, selected, onSelect }: { group: OperatorTraceGroup; selected: string | null; onSelect: (key: string) => void }) {
  const { start, total } = timeAxis(group)
  const ticks = Array.from({ length: TICKS }, (_, index) => (total / (TICKS - 1)) * index)

  return (
    <section className="flex flex-col gap-1">
      <div className="grid grid-cols-[minmax(0,17rem)_minmax(0,1fr)] items-end gap-4 px-2 pb-1">
        <h3 className="text-muted-foreground text-[11px] font-medium tracking-[0.14em] uppercase">
          {group.title}
          {group.startedAt && <span className="ml-2 font-mono tracking-normal normal-case">{formatDateTime(group.startedAt)}</span>}
        </h3>
        <div className="relative h-4 border-b border-border">
          {ticks.map((tick, index) => (
            <span
              key={tick}
              className={`text-muted-foreground absolute bottom-1 font-mono text-[10px] ${tickAlign(index)}`}
              style={{ left: `${(tick / total) * 100}%` }}
            >
              {tickLabel(tick, total)}
            </span>
          ))}
        </div>
      </div>
      <ol className="list-none">
        {group.spans.map((span) => (
          <TraceSpanRow key={span.key} span={span} start={start} total={total} selected={span.key === selected} onSelect={onSelect} />
        ))}
      </ol>
    </section>
  )
}
