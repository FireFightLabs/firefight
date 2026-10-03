import { Link, router, usePage } from "@inertiajs/react"
import { IconPlayerPlay } from "@tabler/icons-react"
import { useState } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { OPERATOR_REGRESSION_RUN_STATUSES } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { operatorHalonRegressionPath, operatorHalonRegressionsPath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { modelName, startedBy } from "@/pages/operator/components/regression-status"
import { Pager } from "@/pages/operator/components/pager"
import { Stat } from "@/pages/operator/components/stat"
import { count } from "@/pages/operator/lib/format"
import { useAction } from "@/pages/operator/lib/use-action"
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

function answers(cases: number): string {
  return cases === 1 ? "rated answer" : `${cases} rated answers`
}

function investigations(cases: number): string {
  return cases === 1 ? "one investigation" : `${cases} investigations`
}

function loadModels() {
  router.reload({ only: ["models"] })
}

function modelOption(model: OperatorHalonRegressionModel): SearchableSelectOption {
  return { value: model.id, label: `${model.name} (${model.provider})` }
}

function RunDialog({ open, onClose, cases, models }: { open: boolean; onClose: () => void; cases: number; models?: OperatorHalonRegressionModel[] }) {
  const [model, setModel] = useState<string | null>(null)
  const { busy, post } = useAction()

  function run() {
    post(operatorHalonRegressionsPath(), { model })
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Run the regression set</DialogTitle>
          <DialogDescription>
            Replays the latest {answers(cases)} on the model you choose. Each replay is a whole investigation on that model,
            so a run costs about what {investigations(cases)} would.
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-2">
          <Label htmlFor="regression-model">Model</Label>
          <SearchableSelect
            value={model}
            onValueChange={setModel}
            options={(models ?? []).map(modelOption)}
            placeholder="Halon's model"
            searchPlaceholder="Search models"
            emptyText={models ? "No model matches" : "Loading models"}
            onOpen={loadModels}
          />
          <p className="text-muted-foreground text-xs">Leave it on Halon&apos;s model to test the prompt as deployed.</p>
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="button" onClick={run} disabled={busy}>
            Run
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
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

      <RunDialog open={running} onClose={closeRun} cases={cases} models={models} />
    </OperatorLayout>
  )
}
