import { Link } from "@inertiajs/react"
import { IconAlertTriangle, IconLoader2 } from "@tabler/icons-react"

import { Card } from "@/components/ui/card"
import { formatDateTime } from "@/lib/formatters"
import { operatorHalonRunPath } from "@/lib/routes"
import { KINDS, MONO_KINDS } from "@/pages/operator/lib/trace-kinds"
import type { OperatorTraceSpan } from "@/types/serializers"

export function SelectedSpan({ span, body, loading }: { span: OperatorTraceSpan; body: string | null | undefined; loading: boolean }) {
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
        <Link href={operatorHalonRunPath(span.runId)} className="text-link text-sm hover:underline">
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
