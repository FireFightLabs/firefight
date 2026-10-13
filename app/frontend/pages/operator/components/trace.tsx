import type { CancelToken } from "@inertiajs/core"
import { router, usePage } from "@inertiajs/react"
import { useEffect, useState } from "react"

import { Card } from "@/components/ui/card"
import { OPERATOR_SPAN_BODY_PROP, OPERATOR_SPAN_MODEL_PARAM, OPERATOR_SPAN_PARAM } from "@/pages/operator/generated/constants"
import { SelectedSpan } from "@/pages/operator/components/selected-span"
import { TraceGroup } from "@/pages/operator/components/trace-group"
import { TraceLegend } from "@/pages/operator/components/trace-legend"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorTraceGroup } from "@/types/serializers"

interface TraceProps extends OperatorPageProps {
  [OPERATOR_SPAN_BODY_PROP]?: string | null
}

function urlSpan(url: string): string | null {
  return new URLSearchParams(url.split("?")[1]).get(OPERATOR_SPAN_PARAM)
}

// Names one loaded content: a span, as people read it or as the model read it.
function bodyKey(spanKey: string, asRead: boolean): string {
  return `${spanKey}:${asRead ? "model" : "shown"}`
}

// Draws each group's spans on its own time axis, with the selected span's details beside them. A span's content loads
// only when it is opened, as people read it, or as the model read it when the operator asks. The URL keeps the open
// span, so a link opens the trace at that span.
export function Trace({ groups }: { groups: OperatorTraceGroup[] }) {
  const page = usePage<TraceProps>()
  const spans = groups.flatMap((group) => group.spans)
  const [selected, setSelected] = useState<string | null>(() => urlSpan(page.url) ?? spans[0]?.key ?? null)
  const [asRead, setAsRead] = useState(false)
  const [loadedFor, setLoadedFor] = useState<string | null>(null)
  const span = spans.find((candidate) => candidate.key === selected) ?? null
  const needsBody = Boolean(span?.hasBody)
  const showsModelReading = asRead && Boolean(span?.readByModel)

  useEffect(() => {
    if (!selected) {
      return
    }
    const wanted = bodyKey(selected, showsModelReading)
    let pending: CancelToken | null = null
    router.reload({
      only: [OPERATOR_SPAN_BODY_PROP],
      data: { [OPERATOR_SPAN_PARAM]: selected, [OPERATOR_SPAN_MODEL_PARAM]: showsModelReading ? "1" : undefined },
      onCancelToken: (token) => {
        pending = token
      },
      onSuccess: () => setLoadedFor(wanted),
    })
    // A request for a span the operator has left is cancelled, so its content never lands over the one they opened.
    return () => pending?.cancel()
  }, [selected, showsModelReading])

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
        <TraceLegend />
        {groups.map((group) => (
          <TraceGroup key={group.key} group={group} selected={selected} onSelect={setSelected} />
        ))}
      </Card>
      <div className="sticky top-6">
        {span && (
          <SelectedSpan
            span={span}
            body={page.props[OPERATOR_SPAN_BODY_PROP]}
            loading={needsBody && loadedFor !== bodyKey(span.key, showsModelReading)}
            asRead={showsModelReading}
            onAsReadChange={setAsRead}
          />
        )}
      </div>
    </div>
  )
}
