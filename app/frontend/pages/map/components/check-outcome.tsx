import { IconExternalLink } from "@tabler/icons-react"

import { MetricChart } from "@/components/charts/metric-chart"
import type { ResourceMapCheckOutcome } from "@/types/serializers"

export function CheckOutcome({ outcome }: { outcome: ResourceMapCheckOutcome }) {
  if (outcome.refusal) {
    return <p className={`text-xs ${outcome.approvalId ? "text-muted-foreground" : "text-destructive"}`}>{outcome.refusal}</p>
  }

  return (
    <div className="flex flex-col gap-2 border-t border-border/60 pt-2">
      {outcome.headline && <p className={`text-sm leading-relaxed ${outcome.failed ? "text-destructive" : ""}`}>{outcome.headline}</p>}
      {outcome.charts.map((chart) => (
        <MetricChart key={chart.id} chart={chart} />
      ))}
      {outcome.text && (
        <pre className="max-h-48 overflow-auto rounded-md bg-muted/40 px-2.5 py-2 font-mono text-[11.5px] leading-relaxed whitespace-pre-wrap">{outcome.text}</pre>
      )}
      {outcome.link && (
        <a href={outcome.link} target="_blank" rel="noreferrer" className="flex w-fit items-center gap-1.5 text-xs text-link hover:underline">
          Open this at its source
          <IconExternalLink className="size-3" />
        </a>
      )}
    </div>
  )
}
