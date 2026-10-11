import { Link, router, usePage } from "@inertiajs/react"
import { IconArrowsDiff, IconPlayerPlay } from "@tabler/icons-react"
import { useState, type ChangeEvent } from "react"

import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { compareOperatorHalonBenchesPath, operatorHalonBenchesPath, operatorHalonBenchPath } from "@/lib/routes"
import { OPERATOR_BENCH_RUN_STATUSES } from "@/pages/operator/generated/constants"
import { benchStartedBy, DIMENSIONS, QUALITY_NOTE, score } from "@/pages/operator/components/bench-score"
import { ModelRunDialog } from "@/pages/operator/components/model-run-dialog"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Pager } from "@/pages/operator/components/pager"
import { Stat } from "@/pages/operator/components/stat"
import { dollars } from "@/pages/operator/lib/format"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorHalonBenchRun, OperatorHalonRegressionModel } from "@/types/serializers"

interface BenchProps extends OperatorPageProps {
  runs: OperatorHalonBenchRun[]
  scenarioCount: number
  tolerance: number
  runBlockedReason: string | null
  defaultRepeats: number
  maxRepeats: number
  defaultBudget: number
  models?: OperatorHalonRegressionModel[]
  page: number
  more: boolean
}

// Two runs are compared at most, the older as the base.
const COMPARED = 2

function pageHref(target: number) {
  return operatorHalonBenchesPath({ page: target })
}

function scenarios(total: number): string {
  return total === 1 ? "the one scenario" : `all ${total} scenarios`
}

function chats(total: number): string {
  return total === 1 ? "one chat" : `${total} chats`
}

function compareNote(chosen: OperatorHalonBenchRun[]): string {
  if (chosen.length < COMPARED) {
    return "Tick two runs to compare them."
  }
  return `Comparing ${formatDateTime(chosen[0].createdAt)} with ${formatDateTime(chosen[1].createdAt)}.`
}

function byAge(left: OperatorHalonBenchRun, right: OperatorHalonBenchRun): number {
  return left.createdAt.localeCompare(right.createdAt)
}

// How many scenarios' repeats agreed, of those replayed more than once.
function agreement(run: OperatorHalonBenchRun): string {
  return run.repeated === 0 ? "-" : `${run.agreeing} of ${run.repeated}`
}

export default function OperatorHalonBench() {
  const { runs, scenarioCount, tolerance, runBlockedReason, defaultRepeats, maxRepeats, defaultBudget, models, page, more } = usePage<BenchProps>().props
  const [running, setRunning] = useState(false)
  const [repeats, setRepeats] = useState(String(defaultRepeats))
  const [budget, setBudget] = useState(String(defaultBudget))
  const [picked, setPicked] = useState<string[]>([])
  const chosen = runs.filter((run) => picked.includes(run.id)).sort(byAge)
  const latest = runs.length > 0 ? runs[0] : undefined

  function openRun() {
    setRunning(true)
  }

  function closeRun() {
    setRunning(false)
  }

  function toggle(id: string) {
    setPicked((current) => (current.includes(id) ? current.filter((each) => each !== id) : [...current, id].slice(-COMPARED)))
  }

  function changeRepeats(event: ChangeEvent<HTMLInputElement>) {
    setRepeats(event.target.value)
  }

  function changeBudget(event: ChangeEvent<HTMLInputElement>) {
    setBudget(event.target.value)
  }

  function compare() {
    router.visit(compareOperatorHalonBenchesPath({ base: chosen[0].id, head: chosen[1].id }))
  }

  return (
    <OperatorLayout title="Bench">
      <PageHeading
        title="Chat bench"
        lead={`Halon replayed on chats written from real failures. Every tool call is answered from the scenario's own world, so only Halon's reasoning changes between two runs. Each scenario is replayed a few times and scored from 0 to 1 on five things. Quality is the mean of right, moved forward and asked when needed, with cost and citing apart, and the total is quality's three and cost. A drop larger than ${tolerance}, or than the spread a run's own repeats showed, is more than the noise.`}
      >
        <div className="flex flex-col items-end gap-1">
          <div className="flex gap-2">
            <Button type="button" variant="outline" size="sm" onClick={compare} disabled={chosen.length < COMPARED}>
              <IconArrowsDiff className="size-3.5" />
              Compare
            </Button>
            <Button type="button" size="sm" onClick={openRun} disabled={runBlockedReason !== null}>
              <IconPlayerPlay className="size-3.5" />
              Run
            </Button>
          </div>
          <span className="text-muted-foreground max-w-64 text-right text-xs">{runBlockedReason ?? compareNote(chosen)}</span>
        </div>
      </PageHeading>

      <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-3">
        <Stat label="Scenarios" value={scenarioCount} note="in config/halon_bench" />
        <Stat label="Latest total" value={score(latest?.total)} note={latest ? `prompt ${latest.promptVersion} on ${latest.model}` : "no run yet"} />
        <Stat label="Noise allowed" value={tolerance} note="at least, or a run's own spread when larger" />
      </div>

      <Card className="gap-0 overflow-hidden py-0">
        {runs.length === 0 ? (
          <p className="text-muted-foreground px-5 py-10 text-center text-sm">
            No bench runs yet. Run one here, from the terminal with bin/rails halon:chat_bench, or let CI run it when Halon changes.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-8">
                  <span className="sr-only">Compare</span>
                </TableHead>
                <TableHead>Started</TableHead>
                <TableHead>Why</TableHead>
                <TableHead>Prompt and model</TableHead>
                <TableHead className="text-right">Total</TableHead>
                <TableHead className="text-right" title={QUALITY_NOTE}>
                  Quality
                </TableHead>
                {DIMENSIONS.map((dimension) => (
                  <TableHead key={dimension.key} className="text-right" title={dimension.label}>
                    {dimension.short}
                  </TableHead>
                ))}
                <TableHead className="text-right" title="Scenarios whose repeats agreed, of those replayed more than once">
                  Agree
                </TableHead>
                <TableHead className="text-right">Spent</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {runs.map((run) => (
                <TableRow key={run.id}>
                  <TableCell>
                    <Checkbox checked={picked.includes(run.id)} onCheckedChange={() => toggle(run.id)} aria-label={`Compare the run of ${formatDateTime(run.createdAt)}`} />
                  </TableCell>
                  <TableCell>
                    <Link href={operatorHalonBenchPath(run.id)} className="hover:underline">
                      {formatDateTime(run.createdAt)}
                    </Link>
                    {run.status === OPERATOR_BENCH_RUN_STATUSES.RUNNING && <span className="text-muted-foreground ml-2 text-xs">{run.pending} replaying</span>}
                    {run.errored > 0 && <span className="text-warning ml-2 text-xs">{run.errored} could not finish</span>}
                  </TableCell>
                  <TableCell>{benchStartedBy(run)}</TableCell>
                  <TableCell>
                    <span className="block">{run.model}</span>
                    <span className="text-muted-foreground font-mono text-xs">{run.promptVersion}</span>
                  </TableCell>
                  <TableCell className="text-right font-mono font-semibold tabular-nums">{score(run.total)}</TableCell>
                  <TableCell className="text-right font-mono tabular-nums">{score(run.quality)}</TableCell>
                  {DIMENSIONS.map((dimension) => (
                    <TableCell key={dimension.key} className="text-right font-mono tabular-nums">
                      {score(run[dimension.key])}
                    </TableCell>
                  ))}
                  <TableCell className="text-right font-mono tabular-nums">{agreement(run)}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    <span className="block">{dollars(run.spentMicros)}</span>
                    <span className="text-muted-foreground block text-xs">judge {dollars(run.judgeSpentMicros)}</span>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
        <Pager page={page} more={more} hrefFor={pageHref} />
      </Card>

      <ModelRunDialog
        open={running}
        onClose={closeRun}
        title="Run the chat bench"
        description={`Replays ${scenarios(scenarioCount)} on the model you choose, each as many times as you say, and scores each one. Each replay is a whole chat on that model, so one pass costs about what ${chats(scenarioCount)} would. The run stops once Halon and the judge together have spent the budget, and keeps what scored before.`}
        action={operatorHalonBenchesPath()}
        models={models}
        extra={{ repeats, budget }}
      >
        <div className="grid grid-cols-2 gap-3">
          <div className="flex flex-col gap-2">
            <Label htmlFor="run-repeats">Replays of each scenario</Label>
            <Input id="run-repeats" type="number" min={1} max={maxRepeats} value={repeats} onChange={changeRepeats} />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="run-budget">Budget in dollars</Label>
            <Input id="run-budget" type="number" min={0.01} step="any" value={budget} onChange={changeBudget} />
          </div>
        </div>
      </ModelRunDialog>
    </OperatorLayout>
  )
}
