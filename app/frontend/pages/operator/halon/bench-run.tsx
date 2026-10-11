import { Link, router, usePage } from "@inertiajs/react"
import { IconArrowsDiff, IconRefresh } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { compareOperatorHalonBenchesPath, operatorHalonBenchesPath } from "@/lib/routes"
import { OPERATOR_BENCH_RUN_STATUSES, OPERATOR_BENCH_SCENARIO_STATUSES } from "@/pages/operator/generated/constants"
import { BenchScenarioStatus, benchStartedBy, DIMENSIONS, QUALITY_NOTE, score, ScoreChange, spreadText } from "@/pages/operator/components/bench-score"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Stat } from "@/pages/operator/components/stat"
import { dollars } from "@/pages/operator/lib/format"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorHalonBenchReplay, OperatorHalonBenchRun, OperatorHalonBenchScenario } from "@/types/serializers"

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
  const scored = `${run.scored} scenarios scored, ${spreadText(run.spread)} between passes`
  return run.pending > 0 ? `${scored}, ${run.pending} replaying` : scored
}

function agreed(run: OperatorHalonBenchRun): string {
  return run.repeated > 0 ? String(run.agreeing) : "-"
}

function agreementNote(run: OperatorHalonBenchRun): string {
  return run.repeated > 0 ? `of ${run.repeated} replayed more than once, within ${run.agreement}` : "each scenario replayed once"
}

function spreadTone(entry: OperatorHalonBenchScenario): string {
  return entry.agrees || entry.spread === undefined ? "text-muted-foreground" : "text-warning"
}

function spentNote(run: OperatorHalonBenchRun): string {
  const judged = `Halon, and ${dollars(run.judgeSpentMicros)} on the judge`
  return run.budgetMicros === null || run.budgetMicros === undefined ? judged : `${judged}, of ${dollars(run.budgetMicros)}`
}

function unfinished(count: number): string {
  return `${count} ${count === 1 ? "replay" : "replays"} could not finish`
}

function counts(replay: OperatorHalonBenchReplay): string {
  const parts = [`${replay.turns} turns`, `${replay.calls} calls`, `${replay.confirmations} confirmed`, dollars(replay.spentMicros)]
  if (replay.notRecorded > 0) {
    parts.push(`${replay.notRecorded} not in the record`)
  }
  return parts.join(" · ")
}

function ReplayHeading({ replay }: { replay: OperatorHalonBenchReplay }) {
  if (replay.status !== OPERATOR_BENCH_SCENARIO_STATUSES.SCORED) {
    return (
      <span className="text-muted-foreground flex items-center gap-2 text-xs font-medium">
        Replay {replay.attempt}
        <BenchScenarioStatus status={replay.status} />
      </span>
    )
  }
  return (
    <span className="text-muted-foreground text-xs font-medium">
      Replay {replay.attempt}, total {score(replay.total)}, quality {score(replay.quality)}
    </span>
  )
}

function ReplayDetail({ replay, repeated }: { replay: OperatorHalonBenchReplay; repeated: boolean }) {
  return (
    <div className="flex flex-col gap-2 text-sm">
      {repeated && <ReplayHeading replay={replay} />}
      {replay.notes.length > 0 && (
        <ul className="flex list-disc flex-col gap-0.5 pl-4">
          {replay.notes.map((note) => (
            <li key={note}>{note}</li>
          ))}
        </ul>
      )}
      {replay.reason && <p className="text-muted-foreground">{replay.reason}</p>}
      {replay.answer && (
        <details>
          <summary className="cursor-pointer text-xs">What Halon answered</summary>
          <p className="mt-1 whitespace-pre-wrap">{replay.answer}</p>
        </details>
      )}
      <span className="text-muted-foreground text-xs">{counts(replay)}</span>
    </div>
  )
}

function ScenarioDetail({ entry }: { entry: OperatorHalonBenchScenario }) {
  const repeated = entry.replays.length > 1
  return (
    <div className="flex flex-col gap-3">
      {entry.replays.map((replay) => (
        <ReplayDetail key={replay.id} replay={replay} repeated={repeated} />
      ))}
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

      <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Stat label="Total" value={score(run.total)} note={totalNote(run)} />
        <Stat label="Quality" value={score(run.quality)} note={QUALITY_NOTE} />
        {DIMENSIONS.map((dimension) => (
          <Stat key={dimension.key} label={dimension.label} value={score(run[dimension.key])} note={dimension.note} />
        ))}
        <Stat label="Repeats agree" value={agreed(run)} note={agreementNote(run)} />
        <Stat
          label="Spent"
          value={dollars(run.spentMicros)}
          note={run.errored > 0 ? unfinished(run.errored) : spentNote(run)}
          tone={run.errored > 0 ? "warning" : "neutral"}
        />
      </div>

      <Card className="gap-0 overflow-hidden py-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Scenario</TableHead>
              <TableHead className="text-right">Total</TableHead>
              <TableHead className="text-right">Since before</TableHead>
              <TableHead className="text-right" title={QUALITY_NOTE}>
                Quality
              </TableHead>
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
              <TableRow key={entry.scenario} className="align-top">
                <TableCell className="max-w-64 whitespace-normal">
                  <span className="block font-medium">{entry.title}</span>
                  <span className="text-muted-foreground font-mono text-xs">{entry.scenario}</span>
                  {entry.status !== OPERATOR_BENCH_SCENARIO_STATUSES.SCORED && (
                    <div className="mt-1">
                      <BenchScenarioStatus status={entry.status} />
                    </div>
                  )}
                </TableCell>
                <TableCell className="text-right">
                  <span className="block font-mono font-semibold tabular-nums">{score(entry.total)}</span>
                  {entry.total !== undefined && <span className={`block text-xs whitespace-nowrap ${spreadTone(entry)}`}>{spreadText(entry.spread)}</span>}
                </TableCell>
                <TableCell className="text-right">
                  <ScoreChange change={entry.change} tolerance={tolerance} />
                </TableCell>
                <TableCell className="text-right font-mono tabular-nums">{score(entry.quality)}</TableCell>
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
