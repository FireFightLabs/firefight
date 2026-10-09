import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { KINDS, MONO_KINDS } from "@/pages/operator/lib/trace-kinds"
import { processToneClasses } from "@/pages/operator/lib/tone"
import type { OperatorTraceSpan } from "@/types/serializers"

// Minimum bar width, as a percentage, so a very short span can still be seen and clicked.
const MIN_WIDTH = 0.6

// Clamps a position to the axis, so a record outside the run's time, such as a later vote, sits at the edge.
function offset(at: string, start: number, total: number): number {
  return Math.min(Math.max(((new Date(at).getTime() - start) / total) * 100, 0), 100)
}

function secondsBetween(from: number, to: number): string {
  return `${((to - from) / 1000).toFixed(1)}s`
}

// Hover text for a span, when it started relative to the group and how long it took.
function whenSaid(span: OperatorTraceSpan, start: number): string {
  const began = new Date(span.startedAt).getTime()
  const at = `at +${secondsBetween(start, began)}`
  return span.endedAt ? `${at}, took ${secondsBetween(began, new Date(span.endedAt).getTime())}` : at
}

export function TraceSpanRow({ span, start, total, selected, onSelect }: { span: OperatorTraceSpan; start: number; total: number; selected: boolean; onSelect: (key: string) => void }) {
  const kind = KINDS[span.kind]
  const KindIcon = kind.icon
  const left = offset(span.startedAt, start, total)
  const width = span.endedAt ? Math.max(offset(span.endedAt, start, total) - left, MIN_WIDTH) : 0

  return (
    <li>
      <button
        type="button"
        onClick={() => onSelect(span.key)}
        aria-pressed={selected}
        className={`grid w-full grid-cols-[minmax(0,17rem)_minmax(0,1fr)] items-center gap-4 rounded-md px-2 py-1.5 text-left transition-colors ${selected ? "bg-surface-selected" : "hover:bg-surface-hover"}`}
      >
        <span className="flex min-w-0 items-center gap-2.5">
          <span className={`flex size-6 shrink-0 items-center justify-center rounded-full border ${processToneClasses(span.tone)}`}>
            <KindIcon className="size-3" stroke={1.8} />
          </span>
          <span className="flex min-w-0 flex-col">
            <span className={`truncate text-[13px] font-medium ${MONO_KINDS.includes(span.kind) ? "font-mono" : ""}`}>{span.title}</span>
            {span.detail && <span className="text-muted-foreground truncate text-xs">{span.detail}</span>}
          </span>
        </span>
        <span className="relative h-5">
          <Tooltip>
            <TooltipTrigger asChild>
              {width > 0 ? (
                <span className={`absolute top-1 h-3 rounded-sm border ${processToneClasses(span.tone)}`} style={{ left: `${left}%`, width: `${Math.min(width, 100 - left)}%` }} />
              ) : (
                <span className={`absolute top-1 size-3 -translate-x-1/2 rotate-45 rounded-[2px] border ${processToneClasses(span.tone)}`} style={{ left: `${left}%` }} />
              )}
            </TooltipTrigger>
            <TooltipContent>{whenSaid(span, start)}</TooltipContent>
          </Tooltip>
        </span>
      </button>
    </li>
  )
}
