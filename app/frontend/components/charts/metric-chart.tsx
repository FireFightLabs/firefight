import { IconExternalLink } from "@tabler/icons-react"
import { CartesianGrid, Line, LineChart, XAxis, YAxis } from "recharts"

import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart"
import type { ChatChart } from "@/types/serializers"

// Neighbouring series get colours far apart, so two containers never read as one line.
const COLORS = [ "var(--chart-1)", "var(--chart-4)", "var(--chart-5)", "var(--chart-3)", "var(--chart-2)" ]

type Row = { at: number } & Record<string, number>

// Every series on one time axis. A series with no point at a moment leaves a gap there instead of a made-up value.
function rowsOf(chart: ChatChart): Row[] {
  const byTime = new Map<number, Row>()
  chart.series.forEach((series, index) => {
    series.points.forEach(([ at, value ]) => {
      const time = new Date(at).getTime()
      const row = byTime.get(time) ?? { at: time }
      row[`s${index}`] = value
      byTime.set(time, row)
    })
  })
  return [ ...byTime.values() ].sort((first, second) => first.at - second.at)
}

function configOf(chart: ChatChart): ChartConfig {
  return Object.fromEntries(chart.series.map((series, index) => [ `s${index}`, { label: series.label, color: COLORS[index % COLORS.length] } ]))
}

function clock(time: number): string {
  return new Date(time).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false })
}

function moment(value: unknown): string {
  return typeof value === "number" ? new Date(value).toLocaleString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", hour12: false }) : ""
}

function tooltipTime(_label: unknown, payload: ReadonlyArray<{ payload?: { at?: number } }>): string {
  return moment(payload?.[0]?.payload?.at)
}

function rangeOf(chart: ChatChart): string {
  return `${moment(new Date(chart.rangeStart).getTime())} to ${clock(new Date(chart.rangeEnd).getTime())}`
}

// One chart a tool returned: its title and unit, a line per series over the range asked for, and a link to the live
// chart on the provider when there is one.
export function MetricChart({ chart }: { chart: ChatChart }) {
  const rows = rowsOf(chart)

  return (
    <figure className="flex min-w-0 flex-col gap-2" aria-label={chart.title}>
      <figcaption className="flex items-baseline justify-between gap-3">
        <span className="truncate text-[13.5px] font-semibold text-foreground">{chart.title}</span>
        <span className="text-muted-foreground shrink-0 text-xs">{chart.unit}</span>
      </figcaption>
      {rows.length === 0 ? (
        <p className="text-muted-foreground text-[13px]">No data points in this range.</p>
      ) : (
        <ChartContainer config={configOf(chart)} className="aspect-auto h-44 w-full">
          <LineChart data={rows} margin={{ left: -16, right: 6, top: 4 }}>
            <CartesianGrid vertical={false} />
            <XAxis dataKey="at" type="number" scale="time" domain={[ "dataMin", "dataMax" ]} tickFormatter={clock} tickLine={false} axisLine={false} minTickGap={32} />
            <YAxis tickLine={false} axisLine={false} width={48} />
            <ChartTooltip content={<ChartTooltipContent labelFormatter={tooltipTime} />} />
            {chart.series.length > 1 && <ChartLegend content={<ChartLegendContent />} />}
            {chart.series.map((series, index) => (
              <Line key={series.label} dataKey={`s${index}`} type="monotone" stroke={`var(--color-s${index})`} strokeWidth={1.6} dot={false} connectNulls={false} isAnimationActive={false} />
            ))}
          </LineChart>
        </ChartContainer>
      )}
      <div className="text-muted-foreground flex flex-wrap items-center justify-between gap-x-3 gap-y-1 text-xs">
        <span>{rangeOf(chart)}</span>
        {chart.sourceUrl && (
          <a href={chart.sourceUrl} target="_blank" rel="noreferrer" className="hover:text-foreground inline-flex items-center gap-1 whitespace-nowrap">
            Open the live chart
            <IconExternalLink className="size-3" />
          </a>
        )}
      </div>
    </figure>
  )
}
