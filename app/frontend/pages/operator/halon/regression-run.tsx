import { Link, router, usePage } from "@inertiajs/react"
import { IconRefresh } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime, percent } from "@/lib/formatters"
import { OPERATOR_REGRESSION_EXPECTED, OPERATOR_REGRESSION_RUN_STATUSES } from "@/lib/generated/constants"
import { operatorHalonRegressionsPath, operatorHalonRunPath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { modelName, RegressionStatus, startedBy } from "@/pages/operator/components/regression-status"
import { Stat } from "@/pages/operator/components/stat"
import { dollars } from "@/pages/operator/lib/format"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorHalonRegressionCase, OperatorHalonRegressionRun } from "@/types/serializers"

interface RegressionRunProps extends OperatorPageProps {
  run: OperatorHalonRegressionRun
  cases: OperatorHalonRegressionCase[]
}

const EXPECTED_LABELS: Record<OperatorHalonRegressionCase["expected"], string> = {
  [OPERATOR_REGRESSION_EXPECTED.CONFIRMED]: "Confirmed",
  [OPERATOR_REGRESSION_EXPECTED.WRONG]: "Marked wrong",
}

function refresh() {
  router.reload()
}

function spent(cases: OperatorHalonRegressionCase[]): number {
  return cases.reduce((sum, entry) => sum + entry.spentMicros, 0)
}

export default function OperatorHalonRegressionRun() {
  const { run, cases } = usePage<RegressionRunProps>().props
  const running = run.status === OPERATOR_REGRESSION_RUN_STATUSES.RUNNING
  const newlyFailing = cases.filter((entry) => entry.newlyFailing).length

  return (
    <OperatorLayout title="Regression run">
      <Link href={operatorHalonRegressionsPath()} className="text-muted-foreground hover:text-foreground mb-3 inline-block text-sm">
        All regression runs
      </Link>
      <PageHeading
        title={`Prompt ${run.promptVersion} on ${modelName(run)}`}
        lead={`${startedBy(run)}, ${formatDateTime(run.createdAt)}. Cases that passed in the run before on the same model and fail now are listed first.`}
      >
        {running && (
          <Button type="button" variant="outline" size="sm" onClick={refresh}>
            <IconRefresh className="size-3.5" />
            Refresh
          </Button>
        )}
      </PageHeading>

      <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Passed" value={percent(run.passed, run.passed + run.failed)} note={`${run.passed} of ${run.passed + run.failed} graded`} />
        <Stat label="Newly failing" value={newlyFailing} note="passed in the run before" tone={newlyFailing > 0 ? "error" : "neutral"} />
        <Stat label="Could not finish" value={run.errored} note={running ? `${run.pending} still replaying` : "not counted either way"} tone={run.errored > 0 ? "warning" : "neutral"} />
        <Stat label="Spent" value={dollars(spent(cases))} note="on the replays" />
      </div>

      <Card className="gap-0 overflow-hidden py-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Case</TableHead>
              <TableHead>Team said</TableHead>
              <TableHead>Result</TableHead>
              <TableHead className="w-1/2">Answers</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {cases.map((entry) => (
              <TableRow key={entry.id} className="align-top">
                <TableCell className="max-w-64">
                  <Link href={operatorHalonRunPath(entry.originalId)} className="block truncate hover:underline">
                    {entry.label}
                  </Link>
                  <span className="text-muted-foreground text-xs">{entry.workspaceName}</span>
                </TableCell>
                <TableCell>{EXPECTED_LABELS[entry.expected]}</TableCell>
                <TableCell>
                  <div className="flex flex-col items-start gap-1">
                    <RegressionStatus status={entry.status} />
                    {entry.newlyFailing && <span className="text-xs text-error">Passed before</span>}
                  </div>
                </TableCell>
                <TableCell className="whitespace-normal">
                  <div className="flex flex-col gap-2 text-sm">
                    <p>
                      <span className="text-muted-foreground">Rated: </span>
                      {entry.ratedAnswer}
                    </p>
                    {entry.answer && (
                      <p>
                        <span className="text-muted-foreground">Replay: </span>
                        {entry.answer}
                      </p>
                    )}
                    {entry.reason && <p className="text-muted-foreground text-xs">{entry.reason}</p>}
                    {entry.replayId && (
                      <Link href={operatorHalonRunPath(entry.replayId)} className="text-xs hover:underline">
                        Open the replay
                      </Link>
                    )}
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </OperatorLayout>
  )
}
