import { router, usePage } from "@inertiajs/react"
import { useEffect, useState } from "react"

import { Card } from "@/components/ui/card"
import { OPERATOR_SPAN_BODY_PROP, OPERATOR_SPAN_PARAM } from "@/lib/generated/constants"
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

// Draws each group's spans on its own time axis, with the selected span's details beside them. A span's content loads
// only when it is opened. The URL keeps the open span, so a link opens the trace at that span.
export function Trace({ groups }: { groups: OperatorTraceGroup[] }) {
  const page = usePage<TraceProps>()
  const spans = groups.flatMap((group) => group.spans)
  const [selected, setSelected] = useState<string | null>(() => urlSpan(page.url) ?? spans[0]?.key ?? null)
  const [loadedFor, setLoadedFor] = useState<string | null>(null)
  const span = spans.find((candidate) => candidate.key === selected) ?? null
  const needsBody = Boolean(span?.hasBody)

  useEffect(() => {
    if (!selected) {
      return
    }
    router.reload({
      only: [OPERATOR_SPAN_BODY_PROP],
      data: { [OPERATOR_SPAN_PARAM]: selected },
      onSuccess: () => setLoadedFor(selected),
    })
  }, [selected])

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
        {span && <SelectedSpan span={span} body={page.props[OPERATOR_SPAN_BODY_PROP]} loading={needsBody && loadedFor !== selected} />}
      </div>
    </div>
  )
}
