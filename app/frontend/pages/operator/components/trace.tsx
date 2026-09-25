import { Link, router, usePage } from "@inertiajs/react"
import {
  IconAlertTriangle,
  IconBrain,
  IconBulb,
  IconChecklist,
  IconCircleCheck,
  IconDatabase,
  IconHandStop,
  IconLoader2,
  IconMessage,
  IconMessageReply,
  IconPlayerPlay,
  IconPlugConnectedX,
  IconSend,
  IconSparkles,
  IconThumbUp,
  IconTool,
  type Icon,
} from "@tabler/icons-react"
import { useEffect, useState } from "react"

import { Card } from "@/components/ui/card"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { formatDateTime } from "@/lib/formatters"
import { OPERATOR_PROCESS_TONES, OPERATOR_SPAN_BODY_PROP, OPERATOR_SPAN_PARAM, OPERATOR_TRACE_KINDS } from "@/lib/generated/constants"
import { operatorHalonRunPath } from "@/lib/routes"
import { processToneClasses } from "@/pages/operator/lib/tone"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorTraceGroup, OperatorTraceSpan } from "@/types/serializers"

type Kind = OperatorTraceSpan["kind"]
type SpanTone = OperatorTraceSpan["tone"]

const TONE_MEANINGS: { tone: SpanTone; meaning: string }[] = [
  { tone: OPERATOR_PROCESS_TONES.INFO, meaning: "Model call or a step in its thinking" },
  { tone: OPERATOR_PROCESS_TONES.OK, meaning: "Went fine" },
  { tone: OPERATOR_PROCESS_TONES.BAD, meaning: "Failed or denied" },
  { tone: OPERATOR_PROCESS_TONES.WARN, meaning: "Worth a look, such as a limit reached" },
  { tone: OPERATOR_PROCESS_TONES.IDLE, meaning: "Skipped or ruled out" },
]

const KINDS: Record<Kind, { label: string; icon: Icon }> = {
  [OPERATOR_TRACE_KINDS.JOB]: { label: "Job", icon: IconPlayerPlay },
  [OPERATOR_TRACE_KINDS.FACTS]: { label: "Facts", icon: IconDatabase },
  [OPERATOR_TRACE_KINDS.MODEL]: { label: "Model call", icon: IconBrain },
  [OPERATOR_TRACE_KINDS.TOOL]: { label: "Tool call through the gateway", icon: IconTool },
  [OPERATOR_TRACE_KINDS.THEORY]: { label: "Theory", icon: IconBulb },
  [OPERATOR_TRACE_KINDS.CHECK]: { label: "Self check", icon: IconChecklist },
  [OPERATOR_TRACE_KINDS.ANSWER]: { label: "Answer", icon: IconCircleCheck },
  [OPERATOR_TRACE_KINDS.STOP]: { label: "Stop", icon: IconHandStop },
  [OPERATOR_TRACE_KINDS.POST]: { label: "Delivery", icon: IconSend },
  [OPERATOR_TRACE_KINDS.PLATFORM]: { label: "Failed platform call", icon: IconPlugConnectedX },
  [OPERATOR_TRACE_KINDS.VERDICT]: { label: "Verdict", icon: IconThumbUp },
  [OPERATOR_TRACE_KINDS.ASK]: { label: "Asked", icon: IconMessage },
  [OPERATOR_TRACE_KINDS.REPLY]: { label: "Reply", icon: IconMessageReply },
  [OPERATOR_TRACE_KINDS.RUN]: { label: "Run started", icon: IconSparkles },
}

const MONO_KINDS: Kind[] = [OPERATOR_TRACE_KINDS.TOOL]
const TICKS = 6
// A span shorter than this share of its clock is still drawn wide enough to see and click.
const MIN_WIDTH = 0.6

interface TraceProps extends OperatorPageProps {
  [OPERATOR_SPAN_BODY_PROP]?: string | null
}

function clock(group: OperatorTraceGroup) {
  const start = new Date(group.startedAt ?? 0).getTime()
  const end = new Date(group.endedAt ?? group.startedAt ?? 0).getTime()
  return { start, total: Math.max(end - start, 1) }
}

// Anything outside the clock, such as a verdict given later, sits at its edge.
function offset(at: string, start: number, total: number): number {
  return Math.min(Math.max(((new Date(at).getTime() - start) / total) * 100, 0), 100)
}

// A short clock is read in tenths of a second, a long one in minutes and hours.
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

// The first tick hangs right of its mark and the last left of it, so neither runs off the ruler.
function tickAlign(index: number): string {
  if (index === 0) {
    return ""
  }
  return index === TICKS - 1 ? "-translate-x-full" : "-translate-x-1/2"
}

function secondsBetween(from: number, to: number): string {
  return `${((to - from) / 1000).toFixed(1)}s`
}

// Where a span sits on the clock, said in words for whoever hovers it.
function whenSaid(span: OperatorTraceSpan, start: number): string {
  const began = new Date(span.startedAt).getTime()
  const at = `at +${secondsBetween(start, began)}`
  return span.endedAt ? `${at}, took ${secondsBetween(began, new Date(span.endedAt).getTime())}` : at
}

function urlSpan(url: string): string | null {
  return new URLSearchParams(url.split("?")[1]).get(OPERATOR_SPAN_PARAM)
}

function SpanRow({ span, start, total, selected, onSelect }: { span: OperatorTraceSpan; start: number; total: number; selected: boolean; onSelect: (key: string) => void }) {
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
        className={`grid w-full grid-cols-[minmax(0,17rem)_minmax(0,1fr)] items-center gap-4 rounded-md px-2 py-1.5 text-left transition-colors ${selected ? "bg-primary/10" : "hover:bg-muted/50"}`}
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

function Group({ group, selected, onSelect }: { group: OperatorTraceGroup; selected: string | null; onSelect: (key: string) => void }) {
  const { start, total } = clock(group)
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
          <SpanRow key={span.key} span={span} start={start} total={total} selected={span.key === selected} onSelect={onSelect} />
        ))}
      </ol>
    </section>
  )
}

// What the shapes and colours mean, since a chart nobody can read is only decoration.
function Legend() {
  return (
    <div className="text-muted-foreground flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-border px-2 pb-4 text-xs">
      <span className="flex items-center gap-2">
        <span className="border-muted-foreground/70 h-3 w-6 rounded-sm border" />
        Took time, from when it started for as long as it ran
      </span>
      <span className="flex items-center gap-2">
        <span className="border-muted-foreground/70 size-2.5 rotate-45 rounded-[2px] border" />
        A moment
      </span>
      {TONE_MEANINGS.map((entry) => (
        <span key={entry.tone} className="flex items-center gap-2">
          <span className={`size-2.5 rounded-full border bg-current! ${processToneClasses(entry.tone)}`} />
          {entry.meaning}
        </span>
      ))}
    </div>
  )
}

function Selected({ span, body, loading }: { span: OperatorTraceSpan; body: string | null | undefined; loading: boolean }) {
  const kind = KINDS[span.kind]

  return (
    <Card className="gap-4 px-5 py-5">
      <div className="flex flex-col gap-1">
        <p className="text-muted-foreground text-[11px] font-medium tracking-[0.14em] uppercase">Selected span</p>
        <h2 className={`text-base font-semibold break-words ${MONO_KINDS.includes(span.kind) ? "font-mono" : ""}`}>{span.title}</h2>
        <p className="text-muted-foreground text-xs">
          {kind.label} · {formatDateTime(span.startedAt)}
        </p>
      </div>
      {span.detail && <p className="text-sm break-words">{span.detail}</p>}
      {span.facts.length > 0 && (
        <dl className="grid grid-cols-[minmax(0,7rem)_minmax(0,1fr)] gap-x-4 gap-y-2 text-[13px]">
          {span.facts.map((fact) => (
            <div key={fact.label} className="contents">
              <dt className="text-muted-foreground">{fact.label}</dt>
              <dd className="min-w-0 font-mono text-xs [overflow-wrap:anywhere]">{fact.value}</dd>
            </div>
          ))}
        </dl>
      )}
      {span.runId && (
        <Link href={operatorHalonRunPath(span.runId)} className="text-primary text-sm hover:underline">
          Open the run's trace
        </Link>
      )}
      {span.hasBody && (
        <div className="flex flex-col gap-2">
          <p className="text-muted-foreground text-[11px] font-medium tracking-[0.14em] uppercase">Content</p>
          {loading ? (
            <p className="text-muted-foreground flex items-center gap-2 text-sm">
              <IconLoader2 className="size-4 animate-spin" />
              Reading
            </p>
          ) : (
            <pre className="bg-muted/40 max-h-[28rem] overflow-auto rounded-md border border-border p-3 font-mono text-xs whitespace-pre-wrap">{body || "Nothing was saved."}</pre>
          )}
          <p className="text-muted-foreground flex items-start gap-1.5 text-xs">
            <IconAlertTriangle className="mt-px size-3.5 shrink-0" />
            This is the customer's data. Read it here, and never copy it into logs or tickets.
          </p>
        </div>
      )}
    </Card>
  )
}

// Spans on one clock per group, and the selected span beside them. Its content is read only when it is opened, and the
// address keeps which one is open, so a trace can be sent to someone at the span that matters.
export function Trace({ groups }: { groups: OperatorTraceGroup[] }) {
  const page = usePage<TraceProps>()
  const spans = groups.flatMap((group) => group.spans)
  const [selected, setSelected] = useState<string | null>(() => urlSpan(page.url) ?? spans[0]?.key ?? null)
  const [loadedFor, setLoadedFor] = useState<string | null>(null)
  const span = spans.find((candidate) => candidate.key === selected) ?? null
  const needsBody = Boolean(span?.hasBody)

  useEffect(() => {
    if (!selected || !needsBody) {
      return
    }
    router.reload({
      only: [OPERATOR_SPAN_BODY_PROP],
      data: { [OPERATOR_SPAN_PARAM]: selected },
      onSuccess: () => setLoadedFor(selected),
    })
  }, [selected, needsBody])

  if (spans.length === 0) {
    return (
      <Card className="px-6 py-10">
        <p className="text-muted-foreground text-sm">Nothing recorded yet.</p>
      </Card>
    )
  }

  return (
    <div className="grid items-start gap-6 xl:grid-cols-[minmax(0,1fr)_22rem]">
      <Card className="gap-6 overflow-hidden px-4 py-5">
        <Legend />
        {groups.map((group) => (
          <Group key={group.key} group={group} selected={selected} onSelect={setSelected} />
        ))}
      </Card>
      <div className="sticky top-6">
        {span && <Selected span={span} body={page.props[OPERATOR_SPAN_BODY_PROP]} loading={needsBody && loadedFor !== selected} />}
      </div>
    </div>
  )
}
