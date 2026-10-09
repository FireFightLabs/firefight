import { Link, usePage } from "@inertiajs/react"
import { IconFileText } from "@tabler/icons-react"
import { useState, type ReactNode } from "react"
import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts"

import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { ChartContainer, ChartLegend, ChartLegendContent, ChartTooltip, ChartTooltipContent, type ChartConfig } from "@/components/ui/chart"
import { OUTCOME_LABELS, labelFor } from "@/components/investigations/labels"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDate, formatDateTime, percent } from "@/lib/formatters"
import { OPERATOR_HALON_ENDINGS, OPERATOR_WINDOWS } from "@/lib/generated/constants"
import { operatorHalonPath, operatorHalonRunPath } from "@/lib/routes"
import { FilterBar } from "@/pages/operator/components/filter-bar"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Pager } from "@/pages/operator/components/pager"
import { ENDING_LABELS, RunEnding } from "@/pages/operator/components/run-ending"
import { Stat } from "@/pages/operator/components/stat"
import { count, dollars, milliseconds, seconds } from "@/pages/operator/lib/format"
import type {
  FilterProps,
  HalonBucket,
  HalonModel,
  HalonPrompt,
  HalonReason,
  HalonTool,
  HalonTotals,
  OperatorPageProps,
} from "@/pages/operator/types"
import type { OperatorHalonRun } from "@/types/serializers"
import { SectionCard } from "@/pages/operator/components/section-card"
import { PromptTextDialog } from "@/pages/operator/components/prompt-text-dialog"

type Ending = OperatorHalonRun["ending"]

interface HalonProps extends OperatorPageProps, FilterProps {
  totals: HalonTotals
  verdicts: Record<string, number>
  buckets: HalonBucket[]
  reasons: HalonReason[]
  tools: HalonTool[]
  model: HalonModel
  prompts: HalonPrompt[]
  limits: { tools: number; prompts: number }
  runs: OperatorHalonRun[]
  page: number
  more: boolean
  ending: Ending | null
}

const ENDINGS: Ending[] = Object.values(OPERATOR_HALON_ENDINGS)

const CHART: ChartConfig = {
  answered: { label: "Answered", color: "var(--chart-3)" },
  stopped: { label: "Stopped", color: "var(--chart-4)" },
  failed: { label: "Failed", color: "var(--destructive)" },
  live: { label: "Working", color: "var(--stage-active)" },
}

function bucketLabel(label: ReactNode) {
  return typeof label === "string" ? formatDateTime(label) : label
}

function tickLabel(window: string) {
  return (at: string) => (window === OPERATOR_WINDOWS.DAY ? new Date(at).toLocaleTimeString("en-US", { hour: "2-digit", hour12: false }) : formatDate(at).replace(/, \d{4}$/, ""))
}

export default function OperatorHalon() {
  const props = usePage<HalonProps>().props
  const { totals, verdicts, buckets, reasons, tools, model, prompts, limits, runs, page, more, ending, filter } = props
  const [readingPrompt, setReadingPrompt] = useState<HalonPrompt | null>(null)
  const filterQuery = { window: filter.window, workspace: filter.workspace ?? undefined }
  const verdictCount = Object.values(verdicts).reduce((sum, votes) => sum + votes, 0)
  const verdictNote = Object.entries(verdicts)
    .map(([outcome, votes]) => `${votes} ${labelFor(OUTCOME_LABELS, outcome)?.toLowerCase() ?? outcome}`)
    .join(", ")

  function runsHref(changes: { ending?: Ending | null; page?: number }) {
    const next = { ending, ...changes }
    return operatorHalonPath({ ...filterQuery, ending: next.ending ?? undefined, page: changes.page })
  }

  function pageHref(target: number) {
    return runsHref({ page: target })
  }

  function closePrompt() {
    setReadingPrompt(null)
  }

  return (
    <OperatorLayout title="Halon">
      <PageHeading
        title="Runs and health"
        lead="How Halon is doing: how runs end, how long they take, what they cost, which tools and model calls fail, and what people said about the answers. Every run opens its trace."
      />
      <FilterBar filter={filter} windows={props.windows} workspaces={props.workspaces} />

      <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Stat label="Runs" value={count(totals.runs)} note={`and ${count(totals.chatTurns)} chat turns${totals.live > 0 ? `, ${totals.live} working` : ""}`} />
        <Stat label="Answered" value={percent(totals.answered, totals.finished)} note={`${totals.answered} of ${totals.finished} finished`} />
        <Stat label="Median time" value={seconds(totals.medianSeconds)} note={`p90 ${seconds(totals.p90Seconds)}`} />
        <Stat label="Spent" value={dollars(totals.spentMicros)} note={`median ${dollars(totals.medianRunMicros)} a run`} />
        <Stat label="Team said" value={count(verdictCount)} note={verdictNote || "no votes on answers yet"} />
      </div>

      <div className="mb-6">
        <SectionCard title="Runs by how they ended" note="Stopped is a limit or a person, failed is our side">
          <div className="px-5 pt-4 pb-2">
            <ChartContainer config={CHART} className="aspect-auto h-56 w-full">
              <BarChart data={buckets} margin={{ left: -20, right: 8 }}>
                <CartesianGrid vertical={false} />
                <XAxis dataKey="at" tickLine={false} axisLine={false} tickFormatter={tickLabel(filter.window)} minTickGap={24} />
                <YAxis allowDecimals={false} tickLine={false} axisLine={false} width={40} />
                <ChartTooltip content={<ChartTooltipContent labelFormatter={bucketLabel} />} />
                <ChartLegend content={<ChartLegendContent />} />
                <Bar dataKey="answered" stackId="runs" fill="var(--color-answered)" />
                <Bar dataKey="stopped" stackId="runs" fill="var(--color-stopped)" />
                <Bar dataKey="failed" stackId="runs" fill="var(--color-failed)" />
                <Bar dataKey="live" stackId="runs" fill="var(--color-live)" radius={[3, 3, 0, 0]} />
              </BarChart>
            </ChartContainer>
          </div>
          {reasons.length > 0 && (
            <ul className="flex flex-wrap gap-2 border-t border-border px-5 py-4">
              {reasons.map((reason) => (
                <li key={`${reason.ending}-${reason.reason}`} className="flex items-center gap-2 rounded-md border border-border px-2.5 py-1 text-xs">
                  <RunEnding ending={reason.ending} />
                  <span className="font-mono">{reason.reason}</span>
                  <span className="text-muted-foreground font-mono">{reason.count}</span>
                </li>
              ))}
            </ul>
          )}
        </SectionCard>
      </div>

      <div className="mb-6 grid gap-6 xl:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <SectionCard title="Tools" note={`The ${limits.tools} most called through the gateway, runs and chats`}>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Tool</TableHead>
                <TableHead className="text-right">Calls</TableHead>
                <TableHead className="text-right">Failed</TableHead>
                <TableHead className="text-right">Refused</TableHead>
                <TableHead className="text-right">Denied</TableHead>
                <TableHead className="text-right">Median</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {tools.map((tool) => (
                <TableRow key={tool.actionKey}>
                  <TableCell className="font-mono text-[13px]">{tool.actionKey}</TableCell>
                  <TableCell className="text-right font-mono">{count(tool.calls)}</TableCell>
                  <TableCell className={`text-right font-mono ${tool.errors > 0 ? "text-error" : "text-muted-foreground"}`}>
                    {percent(tool.errors, tool.calls)}
                  </TableCell>
                  <TableCell className={`text-right font-mono ${tool.refused > 0 ? "text-warning" : "text-muted-foreground"}`}>{tool.refused}</TableCell>
                  <TableCell className={`text-right font-mono ${tool.denied > 0 ? "text-warning" : "text-muted-foreground"}`}>{tool.denied}</TableCell>
                  <TableCell className="text-muted-foreground text-right font-mono">{milliseconds(tool.medianMs)}</TableCell>
                </TableRow>
              ))}
              {tools.length === 0 && (
                <TableRow>
                  <TableCell colSpan={6} className="text-muted-foreground py-8 text-center">No tool calls in this window.</TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </SectionCard>
        <SectionCard title="Model calls" note="Runs, their re-read and chat turns">
          <div className="grid grid-cols-2 gap-3 p-5">
            <Stat label="Calls" value={count(model.calls)} />
            <Stat label="Failed" value={count(model.errors)} note={percent(model.errors, model.calls)} tone={model.errors > 0 ? "error" : "neutral"} />
            <Stat label="Median" value={milliseconds(model.medianMs)} />
            <Stat label="p90" value={milliseconds(model.p90Ms)} />
          </div>
          {Object.keys(model.errorClasses).length > 0 && (
            <ul className="flex flex-col gap-1.5 border-t border-border px-5 py-4 text-xs">
              {Object.entries(model.errorClasses).map(([errorClass, times]) => (
                <li key={errorClass} className="flex justify-between gap-4">
                  <span className="font-mono">{errorClass}</span>
                  <span className="text-muted-foreground font-mono">{times}</span>
                </li>
              ))}
            </ul>
          )}
        </SectionCard>
      </div>

      <div className="mb-6">
        <SectionCard title="Run prompt versions" note={`The latest ${limits.prompts} wordings, each with the runs it started, over all time`}>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Version</TableHead>
                <TableHead>First used</TableHead>
                <TableHead className="text-right">Runs</TableHead>
                <TableHead className="text-right">Answered</TableHead>
                <TableHead className="text-right">Median turns</TableHead>
                <TableHead className="text-right">Median spent</TableHead>
                <TableHead className="text-right">Right · wrong</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {prompts.map((prompt) => (
                <TableRow key={prompt.version}>
                  <TableCell className="font-mono text-[13px]">{prompt.version}</TableCell>
                  <TableCell className="text-muted-foreground">{formatDateTime(prompt.firstSeenAt)}</TableCell>
                  <TableCell className="text-right font-mono">{prompt.runs}</TableCell>
                  <TableCell className="text-right font-mono">{percent(prompt.answered, prompt.finished)}</TableCell>
                  <TableCell className="text-right font-mono">{prompt.medianTurns ?? "-"}</TableCell>
                  <TableCell className="text-right font-mono">{dollars(prompt.medianMicros)}</TableCell>
                  <TableCell className="text-right font-mono">{prompt.confirmed} · {prompt.wrong}</TableCell>
                  <TableCell className="text-right">
                    <Button type="button" variant="ghost" size="sm" onClick={() => setReadingPrompt(prompt)}>
                      <IconFileText className="size-3.5" />
                      Read
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
              {prompts.length === 0 && (
                <TableRow>
                  <TableCell colSpan={8} className="text-muted-foreground py-8 text-center">No run prompt recorded yet.</TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </SectionCard>
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Link
          href={runsHref({ ending: null })}
          preserveScroll
          className={`rounded-full border px-3 py-1 text-xs ${ending === null ? "border-brand-border bg-brand-tint text-brand" : "border-border text-fg-secondary transition-colors hover:bg-surface-hover hover:text-fg-primary"}`}
        >
          All runs
        </Link>
        {ENDINGS.map((choice) => (
          <Link
            key={choice}
            href={runsHref({ ending: choice })}
            preserveScroll
            className={`rounded-full border px-3 py-1 text-xs ${ending === choice ? "border-brand-border bg-brand-tint text-brand" : "border-border text-fg-secondary transition-colors hover:bg-surface-hover hover:text-fg-primary"}`}
          >
            {ENDING_LABELS[choice]}
          </Link>
        ))}
      </div>
      <Card className="gap-0 overflow-hidden py-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Run</TableHead>
              <TableHead>Workspace</TableHead>
              <TableHead>Ended</TableHead>
              <TableHead className="text-right">Turns</TableHead>
              <TableHead className="text-right">Spent</TableHead>
              <TableHead className="text-right">Took</TableHead>
              <TableHead>Started</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {runs.map((run) => (
              <TableRow key={run.id}>
                <TableCell className="max-w-md">
                  <Link href={operatorHalonRunPath(run.id)} className="block truncate hover:underline">{run.label}</Link>
                </TableCell>
                <TableCell className="text-muted-foreground">{run.workspaceName}</TableCell>
                <TableCell>
                  <div className="flex flex-wrap items-center gap-2">
                    <RunEnding ending={run.ending} />
                    {run.ending !== OPERATOR_HALON_ENDINGS.ANSWERED && run.errorSummary && (
                      <span className="text-muted-foreground max-w-56 truncate text-xs">{run.errorSummary}</span>
                    )}
                    {run.notPosted && <span className="text-xs text-error">not posted</span>}
                  </div>
                </TableCell>
                <TableCell className="text-right font-mono">{run.turns}</TableCell>
                <TableCell className="text-right font-mono">{dollars(run.spentMicros)}</TableCell>
                <TableCell className="text-right font-mono">{seconds(run.seconds)}</TableCell>
                <TableCell className="text-muted-foreground">{formatDateTime(run.createdAt)}</TableCell>
              </TableRow>
            ))}
            {runs.length === 0 && (
              <TableRow>
                <TableCell colSpan={7} className="text-muted-foreground py-10 text-center">No runs match.</TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
        <Pager page={page} more={more} hrefFor={pageHref} />
      </Card>
      <PromptTextDialog prompt={readingPrompt} onClose={closePrompt} />
    </OperatorLayout>
  )
}
