import { IconExternalLink } from "@tabler/icons-react"
import { CartesianGrid, Line, LineChart, XAxis, YAxis } from "recharts"

import {
  ChartContainer,
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

const DAY_MS = 24 * 60 * 60 * 1000

function clock(time: number): string {
  return new Date(time).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false })
}

function day(time: number): string {
  return new Date(time).toLocaleDateString("en-US", { month: "short", day: "numeric" })
}

// A chart over more than a day marks its axis with dates, since times alone repeat and read out of order.
function tickFormatterFor(chart: ChatChart): (time: number) => string {
  const span = new Date(chart.rangeEnd).getTime() - new Date(chart.rangeStart).getTime()
  return span > DAY_MS ? day : clock
}

function moment(value: unknown): string {
  return typeof value === "number" ? new Date(value).toLocaleString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", hour12: false }) : ""
}

function tooltipTime(_label: unknown, payload: ReadonlyArray<{ payload?: { at?: number } }>): string {
  return moment(payload?.[0]?.payload?.at)
}

// The end names its day too when the range crosses midnight.
function rangeOf(chart: ChatChart): string {
  const start = new Date(chart.rangeStart).getTime()
  const end = new Date(chart.rangeEnd).getTime()
  const sameDay = new Date(start).toDateString() === new Date(end).toDateString()
  return `${moment(start)} to ${sameDay ? clock(end) : moment(end)}`
}

// Container names are long and made of parts that must stay together, so each series gets its own line.
function Legend({ chart }: { chart: ChatChart }) {
  return (
    <ul className="flex flex-col gap-1 text-xs">
      {chart.series.map((series, index) => (
        <li key={series.label} className="flex min-w-0 items-center gap-2">
          <span aria-hidden className="size-2 shrink-0 rounded-[2px]" style={{ backgroundColor: COLORS[index % COLORS.length] }} />
          <span className="truncate font-mono text-[11.5px] text-foreground/90" title={series.label}>
            {series.label}
          </span>
        </li>
      ))}
    </ul>
  )
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
            <XAxis dataKey="at" type="number" scale="time" domain={[ "dataMin", "dataMax" ]} tickFormatter={tickFormatterFor(chart)} tickLine={false} axisLine={false} minTickGap={32} />
            <YAxis tickLine={false} axisLine={false} width={48} />
            <ChartTooltip content={<ChartTooltipContent labelFormatter={tooltipTime} />} />
            {chart.series.map((series, index) => (
              <Line key={series.label} dataKey={`s${index}`} type="monotone" stroke={`var(--color-s${index})`} strokeWidth={1.6} dot={false} connectNulls={false} isAnimationActive={false} />
            ))}
          </LineChart>
        </ChartContainer>
      )}
      {rows.length > 0 && chart.series.length > 1 && <Legend chart={chart} />}
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
