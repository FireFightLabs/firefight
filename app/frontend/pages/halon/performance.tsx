import { Head, Link, router, usePage } from "@inertiajs/react"
import { IconBrain } from "@tabler/icons-react"
import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Card } from "@/components/ui/card"
import { ChartContainer, ChartLegend, ChartLegendContent, ChartTooltip, ChartTooltipContent, type ChartConfig } from "@/components/ui/chart"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { formatDate } from "@/lib/formatters"
import { halonPerformancePath, incidentPath, investigationPath } from "@/lib/routes"
import type { SharedProps } from "@/types"
import type { HalonMistake, HalonPerformance } from "@/types/serializers"

interface PerformanceProps extends SharedProps {
  performance: HalonPerformance
  windows: number[]
}

const CHART: ChartConfig = {
  confirmed: { label: "Right", color: "var(--success)" },
  partial: { label: "Partly right", color: "var(--warning)" },
  wrong: { label: "Wrong", color: "var(--error)" },
  notRated: { label: "Not rated", color: "var(--chart-5)" },
}

function percent(part: number, whole: number): string {
  return whole > 0 ? `${Math.round((part / whole) * 100)}%` : "-"
}

function duration(seconds: number | undefined): string {
  if (seconds === undefined) {
    return "-"
  }
  if (seconds < 60) {
    return `${seconds}s`
  }
  const minutes = Math.round(seconds / 60)
  return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)}h ${minutes % 60}m`
}

// A week is a calendar date, so it is read as one wherever the viewer is, never shifted by their time zone.
function weekLabel(startsOn: string): string {
  return new Date(`${startsOn}T00:00:00`).toLocaleDateString("en-US", { month: "short", day: "numeric" })
}

function tooltipLabel(label: React.ReactNode) {
  return typeof label === "string" ? `Week of ${weekLabel(label)}` : label
}

function chooseWindow(value: string) {
  if (!value) {
    return
  }
  router.get(halonPerformancePath({ days: value }), {}, { preserveScroll: true, preserveState: true })
}

function Stat({ label, value, note }: { label: string; value: string; note: string }) {
  return (
    <Card className="flex min-w-0 flex-col gap-1 px-4 py-3">
      <span className="text-[11px] font-medium tracking-[0.12em] text-fg-secondary uppercase">{label}</span>
      <span className="font-mono text-2xl font-semibold text-fg-primary tabular-nums">{value}</span>
      <span className="truncate text-xs text-fg-secondary">{note}</span>
    </Card>
  )
}

function Mistake({ mistake }: { mistake: HalonMistake }) {
  return (
    <li className="flex flex-col gap-2 border-b border-border px-5 py-4 last:border-b-0">
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        {mistake.incidentId ? (
          <Link href={incidentPath(mistake.incidentId)} className="font-medium text-fg-primary hover:underline">
            {mistake.label}
          </Link>
        ) : (
          <span className="font-medium text-fg-primary">{mistake.label}</span>
        )}
        {mistake.markedAt && <span className="text-xs text-fg-secondary">Marked wrong {formatDate(mistake.markedAt)}</span>}
      </div>
      <p className="text-sm text-fg-body">
        <span className="text-fg-secondary">Halon said: </span>
        {mistake.summary}
      </p>
      {mistake.cause && <p className="text-xs text-fg-secondary">The cause it gave: {mistake.cause}</p>}
      {mistake.lessons.length > 0 ? (
        <ul className="flex flex-col gap-1">
          {mistake.lessons.map((lesson) => (
            <li key={lesson.id} className="flex items-start gap-1.5 text-sm text-fg-body">
              <IconBrain className="mt-0.5 size-3.5 shrink-0 text-brand" />
              <span>
                {lesson.text}
                <span className="ml-1.5 text-xs text-fg-secondary">{lesson.confirmed ? "confirmed" : "unconfirmed"}</span>
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-xs text-fg-secondary">Nothing learned from this incident yet.</p>
      )}
      <Link href={investigationPath(mistake.investigationId)} className="w-fit text-xs text-fg-secondary hover:text-fg-primary hover:underline">
        Open the investigation
      </Link>
    </li>
  )
}

export default function HalonPerformancePage() {
  const { performance, windows } = usePage<PerformanceProps>().props
  const answeredNote = performance.ended > 0 ? `${performance.answered} of ${performance.ended} finished runs` : "no finished runs yet"

  return (
    <AuthenticatedLayout title="Performance">
      <Head title="Performance" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <p className="max-w-prose text-sm text-fg-secondary">
            How Halon has done for your team, from what your team said about its answers and what came of its fixes.
            Nothing here is estimated.
          </p>
          <ToggleGroup type="single" variant="outline" size="sm" value={String(performance.days)} onValueChange={chooseWindow} aria-label="Time window">
            {windows.map((days) => (
              <ToggleGroupItem key={days} value={String(days)} className="px-3">
                {days} days
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        </div>

        {performance.runs === 0 ? (
          <Card className="px-5 py-10 text-center text-sm text-fg-secondary">
            Halon has not investigated anything in the last {performance.days} days.
          </Card>
        ) : (
          <>
            <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
              <Stat label="Right" value={percent(performance.confirmed, performance.rated)} note={`${performance.rated} of ${performance.answered} answers rated`} />
              <Stat label="Answered" value={percent(performance.answered, performance.ended)} note={answeredNote} />
              <Stat label="Time to answer" value={duration(performance.medianSeconds)} note="median" />
              <Stat label="Investigations" value={String(performance.runs)} note={`in the last ${performance.days} days`} />
            </div>

            <Card className="gap-0 overflow-hidden py-0">
              <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b border-border px-5 py-4">
                <h2 className="text-sm font-semibold text-fg-primary">What your team said of each answer</h2>
                <span className="text-xs text-fg-secondary">
                  {performance.confirmed} right, {performance.partial} partly right, {performance.wrong} wrong, {performance.notRated} not rated
                </span>
              </div>
              <div className="px-5 pt-4 pb-2">
                <ChartContainer config={CHART} className="aspect-auto h-56 w-full">
                  <BarChart data={performance.weeks} margin={{ left: -20, right: 8 }} accessibilityLayer>
                    <CartesianGrid vertical={false} />
                    <XAxis dataKey="startsOn" tickLine={false} axisLine={false} tickFormatter={weekLabel} minTickGap={24} />
                    <YAxis allowDecimals={false} tickLine={false} axisLine={false} />
                    <ChartTooltip content={<ChartTooltipContent labelFormatter={tooltipLabel} />} />
                    <ChartLegend content={<ChartLegendContent />} />
                    <Bar dataKey="confirmed" stackId="answers" fill="var(--color-confirmed)" />
                    <Bar dataKey="partial" stackId="answers" fill="var(--color-partial)" />
                    <Bar dataKey="wrong" stackId="answers" fill="var(--color-wrong)" />
                    <Bar dataKey="notRated" stackId="answers" fill="var(--color-notRated)" radius={[ 3, 3, 0, 0 ]} />
                  </BarChart>
                </ChartContainer>
                <p className="pt-1 pb-2 text-xs text-fg-secondary">Weeks start on Monday. The first and last weeks are only partly in the window.</p>
              </div>
            </Card>

            <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
              <Stat label="Fixes proposed" value={String(performance.fixesProposed)} note="with an answer" />
              <Stat label="Applied" value={String(performance.fixesApplied)} note="and kept" />
              <Stat label="Undone" value={String(performance.fixesUndone)} note="applied, then reversed" />
              <Stat label="Cancelled" value={String(performance.fixesCancelled)} note="stopped while applying" />
            </div>

            <Card className="gap-0 overflow-hidden py-0">
              <div className="border-b border-border px-5 py-4">
                <h2 className="text-sm font-semibold text-fg-primary">Where Halon was wrong</h2>
                <p className="mt-1 text-xs text-fg-secondary">Answers from runs in the last {performance.days} days that your team marked wrong, newest first, with what Halon learned from each incident.</p>
              </div>
              {performance.mistakes.length === 0 ? (
                <p className="px-5 py-8 text-center text-sm text-fg-secondary">No answer from runs in the last {performance.days} days was marked wrong.</p>
              ) : (
                <ul>
                  {performance.mistakes.map((mistake) => (
                    <Mistake key={mistake.id} mistake={mistake} />
                  ))}
                </ul>
              )}
            </Card>
          </>
        )}
      </div>
    </AuthenticatedLayout>
  )
}
