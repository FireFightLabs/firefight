import { Link, router, usePage } from "@inertiajs/react"
import { IconArrowsDiff, IconRefresh } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { compareOperatorHalonBenchesPath, operatorHalonBenchesPath } from "@/lib/routes"
import { OPERATOR_BENCH_RUN_STATUSES, OPERATOR_BENCH_SCENARIO_STATUSES } from "@/pages/operator/generated/constants"
import { BenchScenarioStatus, benchStartedBy, DIMENSIONS, score, ScoreChange } from "@/pages/operator/components/bench-score"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Stat } from "@/pages/operator/components/stat"
import { dollars } from "@/pages/operator/lib/format"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorHalonBenchRun, OperatorHalonBenchScenario } from "@/types/serializers"

interface BenchRunProps extends OperatorPageProps {
  run: OperatorHalonBenchRun
  previousId: string | null
  scenarios: OperatorHalonBenchScenario[]
  tolerance: number
}

function refresh() {
  router.reload()
}

function totalNote(run: OperatorHalonBenchRun): string {
  return run.pending > 0 ? `${run.scored} scored, ${run.pending} replaying` : `${run.scored} scored`
}

function counts(entry: OperatorHalonBenchScenario): string {
  const parts = [`${entry.turns} turns`, `${entry.calls} calls`, `${entry.confirmations} confirmed`, dollars(entry.spentMicros)]
  if (entry.notRecorded > 0) {
    parts.push(`${entry.notRecorded} not in the record`)
  }
  return parts.join(" · ")
}

function ScenarioDetail({ entry }: { entry: OperatorHalonBenchScenario }) {
  return (
    <div className="flex flex-col gap-2 text-sm">
      {entry.notes.length > 0 && (
        <ul className="flex list-disc flex-col gap-0.5 pl-4">
          {entry.notes.map((note) => (
            <li key={note}>{note}</li>
          ))}
        </ul>
      )}
      {entry.reason && <p className="text-muted-foreground">{entry.reason}</p>}
      {entry.answer && (
        <details>
          <summary className="cursor-pointer text-xs">What Halon answered</summary>
          <p className="mt-1 whitespace-pre-wrap">{entry.answer}</p>
        </details>
      )}
      <span className="text-muted-foreground text-xs">{counts(entry)}</span>
    </div>
  )
}

export default function OperatorHalonBenchRun() {
  const { run, previousId, scenarios, tolerance } = usePage<BenchRunProps>().props
  const running = run.status === OPERATOR_BENCH_RUN_STATUSES.RUNNING

  return (
    <OperatorLayout title="Bench run">
      <Link href={operatorHalonBenchesPath()} className="text-muted-foreground hover:text-foreground mb-3 inline-block text-sm">
        All bench runs
      </Link>
      <PageHeading
        title={`Prompt ${run.promptVersion} on ${run.model}`}
        lead={`${benchStartedBy(run)}, ${formatDateTime(run.createdAt)}. Scenarios that dropped most since the run before on the same model are listed first.`}
      >
        {previousId && (
          <Button asChild variant="outline" size="sm">
            <Link href={compareOperatorHalonBenchesPath({ base: previousId, head: run.id })}>
              <IconArrowsDiff className="size-3.5" />
              Compare with the run before
            </Link>
          </Button>
        )}
        {running && (
          <Button type="button" variant="outline" size="sm" onClick={refresh}>
            <IconRefresh className="size-3.5" />
            Refresh
          </Button>
        )}
      </PageHeading>

      {run.stoppedReason && <p className="text-warning mb-4 text-sm">{run.stoppedReason}</p>}

      <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-6">
        <Stat label="Total" value={score(run.total)} note={totalNote(run)} />
        {DIMENSIONS.map((dimension) => (
          <Stat key={dimension.key} label={dimension.label} value={score(run[dimension.key])} note={dimension.note} />
        ))}
        <Stat label="Spent" value={dollars(run.spentMicros)} note={run.errored > 0 ? `${run.errored} could not finish` : "on Halon's model calls"} tone={run.errored > 0 ? "warning" : "neutral"} />
      </div>

      <Card className="gap-0 overflow-hidden py-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Scenario</TableHead>
              <TableHead className="text-right">Total</TableHead>
              <TableHead className="text-right">Since before</TableHead>
              {DIMENSIONS.map((dimension) => (
                <TableHead key={dimension.key} className="text-right" title={dimension.label}>
                  {dimension.short}
                </TableHead>
              ))}
              <TableHead className="w-2/5">What happened</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {scenarios.map((entry) => (
              <TableRow key={entry.id} className="align-top">
                <TableCell className="max-w-64 whitespace-normal">
                  <span className="block font-medium">{entry.title}</span>
                  <span className="text-muted-foreground font-mono text-xs">{entry.scenario}</span>
                  {entry.status !== OPERATOR_BENCH_SCENARIO_STATUSES.SCORED && (
                    <div className="mt-1">
                      <BenchScenarioStatus status={entry.status} />
                    </div>
                  )}
                </TableCell>
                <TableCell className="text-right font-mono font-semibold tabular-nums">{score(entry.total)}</TableCell>
                <TableCell className="text-right">
                  <ScoreChange change={entry.change} tolerance={tolerance} />
                </TableCell>
                {DIMENSIONS.map((dimension) => (
                  <TableCell key={dimension.key} className="text-right font-mono tabular-nums">
                    {score(entry[dimension.key])}
                  </TableCell>
                ))}
                <TableCell className="whitespace-normal">
                  <ScenarioDetail entry={entry} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </OperatorLayout>
  )
}
