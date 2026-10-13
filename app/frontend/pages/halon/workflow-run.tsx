import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { useCan } from "@/lib/permissions"
import { useLiveRun } from "@/pages/halon/hooks/use-live-run"
import { RunCallsCard } from "@/pages/halon/components/workflows/run-calls-card"
import { RunHeader } from "@/pages/halon/components/workflows/run-header"
import { RunStepRow } from "@/pages/halon/components/workflows/run-step-row"
import type { WorkflowRunPageProps } from "@/pages/halon/components/workflows/types"

export default function HalonWorkflowRunPage() {
  const { run } = usePage<WorkflowRunPageProps>().props
  const canManage = useCan("workflows")
  useLiveRun(run.status)

  return (
    <AuthenticatedLayout title={run.workflowName}>
      <Head title={`${run.workflowName} run - Workflows`} />
      <div className="mx-auto flex w-full max-w-5xl flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <RunHeader run={run} canManage={canManage} />
        {run.detailsPruned ? (
          <Card>
            <CardContent className="py-6 text-sm text-muted-foreground">
              Its details were dropped after the workspace&apos;s run history ended, so only this line is kept.
            </CardContent>
          </Card>
        ) : (
          <>
            <Card>
              <CardHeader>
                <CardTitle>Steps</CardTitle>
                <CardDescription className="mt-1">
                  {run.test ? "A test run. Every change shows what it would do unless it was made for real." : "In the order they ran."}
                </CardDescription>
              </CardHeader>
              <CardContent>
                {run.steps.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No step has started yet.</p>
                ) : (
                  <ol className="flex flex-col divide-y">
                    {run.steps.map((step) => <RunStepRow key={`${step.key}-${step.iteration}`} step={step} />)}
                  </ol>
                )}
              </CardContent>
            </Card>
            <RunCallsCard run={run} />
          </>
        )}
      </div>
    </AuthenticatedLayout>
  )
}
