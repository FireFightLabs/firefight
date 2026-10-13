import { useState } from "react"
import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { WORKFLOW_PAGE_TAB_QUERY, WORKFLOW_PAGE_TABS, type WorkflowPageTab } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { replaceQuery } from "@/lib/query"
import { LibraryItemsCard } from "@/pages/halon/components/workflow-library/library-items-card"
import { WorkflowsCard as LibraryWorkflowsCard } from "@/pages/halon/components/workflow-library/workflows-card"
import { DoneCard } from "@/pages/halon/components/workflows/done-card"
import { LibraryMenu } from "@/pages/halon/components/workflows/library-menu"
import { PublishRequestsCard } from "@/pages/halon/components/workflows/publish-requests-card"
import { RunsTable } from "@/pages/halon/components/workflows/runs-table"
import type { WorkflowsPageProps } from "@/pages/halon/components/workflows/types"
import { WorkflowsCard } from "@/pages/halon/components/workflows/workflows-card"

const [ WORKFLOWS_TAB, RUNS_TAB, DONE_TAB, LIBRARY_TAB ] = WORKFLOW_PAGE_TABS

function chosenTab(value: string | null): WorkflowPageTab | undefined {
  return WORKFLOW_PAGE_TABS.find((tab) => tab === value)
}

function tabFromUrl(): WorkflowPageTab {
  return chosenTab(new URLSearchParams(window.location.search).get(WORKFLOW_PAGE_TAB_QUERY)) ?? WORKFLOWS_TAB
}

export default function HalonWorkflowsPage() {
  const { workflows, done, doneRuns, runs, runsPage, templates, publishRequests, timeZones, libraryItems, libraryWorkflows, canCreate } = usePage<WorkflowsPageProps>().props
  const canManage = useCan("workflows")
  const [ tab, setTab ] = useState(tabFromUrl)
  const newWorkflow = canCreate ? <LibraryMenu templates={templates} timeZones={timeZones} /> : null

  function switchTab(value: string) {
    const chosen = chosenTab(value)
    if (!chosen) {
      return
    }
    setTab(chosen)
    replaceQuery({ [WORKFLOW_PAGE_TAB_QUERY]: chosen, page: null })
  }

  return (
    <AuthenticatedLayout title="Workflows">
      <Head title="Workflows" />
      <Tabs value={tab} onValueChange={switchTab} className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <TabsList>
          <TabsTrigger value={WORKFLOWS_TAB} className="px-3">Workflows</TabsTrigger>
          <TabsTrigger value={RUNS_TAB} className="px-3">Runs</TabsTrigger>
          <TabsTrigger value={DONE_TAB} className="px-3">Done</TabsTrigger>
          <TabsTrigger value={LIBRARY_TAB} className="px-3">Library</TabsTrigger>
        </TabsList>
        <TabsContent value={WORKFLOWS_TAB} className="flex flex-col gap-6">
          {publishRequests.length > 0 && <PublishRequestsCard requests={publishRequests} />}
          <WorkflowsCard workflows={workflows} canManage={canManage} action={newWorkflow} />
        </TabsContent>
        <TabsContent value={RUNS_TAB}>
          <Card>
            <CardHeader>
              <CardTitle>Runs</CardTitle>
              <CardDescription className="mt-1">Every run of every workflow, newest first. A run keeps its details for the workspace&apos;s run history, and a pinned run keeps them for good.</CardDescription>
            </CardHeader>
            <CardContent className="p-0">
              {runs.length === 0 ? (
                <p className="px-6 pb-6 text-sm text-muted-foreground">No workflow has run yet.</p>
              ) : (
                <RunsTable runs={runs} page={runsPage} showWorkflow />
              )}
            </CardContent>
          </Card>
        </TabsContent>
        <TabsContent value={DONE_TAB}>
          <DoneCard done={done} runs={doneRuns} canManage={canManage} timeZones={timeZones} />
        </TabsContent>
        <TabsContent value={LIBRARY_TAB} className="flex flex-col gap-6">
          <LibraryWorkflowsCard workflows={libraryWorkflows} canCreate={canCreate} canManage={canManage} />
          <LibraryItemsCard items={libraryItems} canCreate={canCreate} />
        </TabsContent>
      </Tabs>
    </AuthenticatedLayout>
  )
}
