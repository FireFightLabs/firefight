import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { useCan } from "@/lib/permissions"
import { ReachCard } from "@/pages/halon/components/workflows/reach-card"
import { RunsTable } from "@/pages/halon/components/workflows/runs-table"
import { SettingsCard } from "@/pages/halon/components/workflows/settings-card"
import { StepsCard } from "@/pages/halon/components/workflows/steps-card"
import { SuggestionsCard } from "@/pages/halon/components/workflows/suggestions-card"
import type { WorkflowPageProps } from "@/pages/halon/components/workflows/types"
import { WorkflowHeader } from "@/pages/halon/components/workflows/workflow-header"

export default function HalonWorkflowPage() {
  const { workflow, runs, runsPage, myPublishRequest, teams } = usePage<WorkflowPageProps>().props
  const canManage = useCan("workflows")

  return (
    <AuthenticatedLayout title={workflow.name}>
      <Head title={`${workflow.name} - Workflows`} />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <WorkflowHeader workflow={workflow} canManage={canManage} publishRequest={myPublishRequest} />
        <SuggestionsCard workflow={workflow} canManage={canManage} />
        <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
          <div className="xl:col-span-2"><StepsCard workflow={workflow} /></div>
          <ReachCard workflow={workflow} />
        </div>
        <Card>
          <CardHeader>
            <CardTitle>Runs</CardTitle>
            <CardDescription className="mt-1">Newest first. Test runs are marked.</CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            {runs.length === 0 ? (
              <p className="px-6 pb-6 text-sm text-muted-foreground">It has not run yet.</p>
            ) : (
              <RunsTable runs={runs} page={runsPage} showWorkflow={false} />
            )}
          </CardContent>
        </Card>
        <SettingsCard key={workflow.id} workflow={workflow} teams={teams} canManage={canManage} />
      </div>
    </AuthenticatedLayout>
  )
}
