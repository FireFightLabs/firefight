import { Link, usePage } from "@inertiajs/react"
import { IconPlayerPlay } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { OPERATOR_REGRESSION_RUN_STATUSES } from "@/pages/operator/generated/constants"
import { operatorHalonRegressionPath, operatorHalonRegressionsPath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { modelName, startedBy } from "@/pages/operator/components/regression-status"
import { Pager } from "@/pages/operator/components/pager"
import { RegressionRunDialog } from "@/pages/operator/components/regression-run-dialog"
import { Stat } from "@/pages/operator/components/stat"
import { count } from "@/pages/operator/lib/format"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorHalonRegressionModel, OperatorHalonRegressionRun } from "@/types/serializers"

interface RegressionProps extends OperatorPageProps {
  runs: OperatorHalonRegressionRun[]
  casesAvailable: number
  caseLimit: number
  workspacesOptedIn: number
  promptVersion: string
  runBlockedReason: string | null
  models?: OperatorHalonRegressionModel[]
  page: number
  more: boolean
}

function pageHref(target: number) {
  return operatorHalonRegressionsPath({ page: target })
}

export default function OperatorHalonRegression() {
  const { runs, casesAvailable, caseLimit, workspacesOptedIn, promptVersion, runBlockedReason, models, page, more } = usePage<RegressionProps>().props
  const [running, setRunning] = useState(false)
  const cases = Math.min(casesAvailable, caseLimit)

  function openRun() {
    setRunning(true)
  }

  function closeRun() {
    setRunning(false)
  }

  return (
    <OperatorLayout title="Regression">
      <PageHeading
        title="Regression"
        lead="The latest answers teams confirmed or marked wrong, replayed on a version of Halon. A replay answers every tool call from what the original run read, so only Halon's reasoning changes. A confirmed answer passes when the replay names the same cause, and a wrong one passes when the replay does not repeat it. A run starts by itself the first time a new prompt is deployed."
      >
        <div className="flex flex-col items-end gap-1">
          <Button type="button" size="sm" onClick={openRun} disabled={runBlockedReason !== null}>
            <IconPlayerPlay className="size-3.5" />
            Run
          </Button>
          {runBlockedReason && <span className="text-muted-foreground max-w-64 text-right text-xs">{runBlockedReason}</span>}
        </div>
      </PageHeading>

      <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-3">
        <Stat label="Rated answers" value={count(casesAvailable)} note={`the latest ${caseLimit} are replayed in a run`} />
        <Stat label="Workspaces opted in" value={count(workspacesOptedIn)} note="Settings, Workspace, Halon" />
        <Stat label="Prompt deployed" value={promptVersion} />
      </div>

      <Card className="gap-0 overflow-hidden py-0">
        {runs.length === 0 ? (
          <p className="text-muted-foreground px-5 py-10 text-center text-sm">
            No regression runs yet. One starts by itself when a new prompt is deployed and a workspace that opted in has a rated answer.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Started</TableHead>
                <TableHead>Why</TableHead>
                <TableHead>Prompt</TableHead>
                <TableHead>Model</TableHead>
                <TableHead className="text-right">Passed</TableHead>
                <TableHead className="text-right">Failed</TableHead>
                <TableHead className="text-right">Could not finish</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {runs.map((run) => (
                <TableRow key={run.id}>
                  <TableCell>
                    <Link href={operatorHalonRegressionPath(run.id)} className="hover:underline">
                      {formatDateTime(run.createdAt)}
                    </Link>
                    {run.status === OPERATOR_REGRESSION_RUN_STATUSES.RUNNING && <span className="text-muted-foreground ml-2 text-xs">{run.pending} replaying</span>}
                  </TableCell>
                  <TableCell>{startedBy(run)}</TableCell>
                  <TableCell className="font-mono text-xs">{run.promptVersion}</TableCell>
                  <TableCell>{modelName(run)}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {run.passed} of {run.total}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">{run.failed}</TableCell>
                  <TableCell className="text-right tabular-nums">{run.errored}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
        <Pager page={page} more={more} hrefFor={pageHref} />
      </Card>

      <RegressionRunDialog open={running} onClose={closeRun} cases={cases} models={models} />
    </OperatorLayout>
  )
}
