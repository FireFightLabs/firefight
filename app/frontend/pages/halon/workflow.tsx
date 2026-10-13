import { Head, usePage, usePoll } from "@inertiajs/react"
import { useState } from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { CanvasHeader } from "@/pages/halon/components/workflow/canvas-header"
import { PublishRequestsNotice } from "@/pages/halon/components/workflow/publish-requests-notice"
import { SettingsView } from "@/pages/halon/components/workflow/settings-view"
import { SuggestionsBanner } from "@/pages/halon/components/workflow/suggestions-banner"
import { VersionActions } from "@/pages/halon/components/workflow/version-actions"
import { VersionsView } from "@/pages/halon/components/workflow/versions-view"
import { WorkflowAlerts } from "@/pages/halon/components/workflow/workflow-alerts"
import { WorkflowControls } from "@/pages/halon/components/workflow/workflow-controls"
import { WorkflowEditor } from "@/pages/halon/components/workflow/workflow-editor"
import { useCanvasActionsValue } from "@/pages/halon/hooks/use-canvas-actions-value"
import { useCanvasView } from "@/pages/halon/hooks/use-canvas-view"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"
import { CANVAS_VISIT, useWorkflowEdits } from "@/pages/halon/hooks/use-workflow-edits"
import { CanvasActionsContext } from "@/pages/halon/lib/workflow/canvas-actions"
import { type Selection, VIEWS, type WorkflowPageProps } from "@/pages/halon/lib/workflow/types"

// Someone else's change, or a suggestion of Halon's, shows on the canvas within this long.
const REFRESH_EVERY_MS = 5000

export default function WorkflowCanvasPage() {
  const { workflow, document, versions, suggestions, halonChanges, stepKinds, triggerKinds, tools, publishRequests, otherWorkflows, timeZones, teams,
    myPublishRequest } = usePage<WorkflowPageProps>().props
  const access = useWorkflowAccess()
  const [ selection, setSelection ] = useState<Selection>(null)
  const { view, show, openVersion, leaveVersion } = useCanvasView(workflow.id)
  const send = useWorkflowEdits(workflow.id, document)
  const actions = useCanvasActionsValue(workflow.id, send, setSelection)
  const editable = access.build && document.editable
  const current = document.editable
  usePoll(REFRESH_EVERY_MS, { only: CANVAS_VISIT.only })

  return (
    <AuthenticatedLayout title="Workflow" sidebarCollapsed>
      <Head title={`${workflow.name} — Workflow`} />
      <CanvasActionsContext value={actions}>
        <div className="-mt-6 flex h-[calc(100dvh-var(--header-height))] flex-col overflow-hidden">
          <CanvasHeader
            workflow={workflow}
            document={document}
            suggestionCount={current ? suggestions.length : 0}
            view={view}
            onView={show}
            actions={(
              <>
                <WorkflowControls workflow={workflow} />
                <VersionActions workflow={workflow} document={document} myPublishRequest={myPublishRequest} onLeaveVersion={leaveVersion} />
              </>
            )}
          />
          <WorkflowAlerts workflow={workflow} />
          {access.manage && current && publishRequests.length > 0 && <PublishRequestsNotice requests={publishRequests} />}
          {view === VIEWS.EDITOR && current && suggestions.length > 0 && <SuggestionsBanner workflowId={workflow.id} suggestions={suggestions} />}
          {view === VIEWS.EDITOR ? (
            <WorkflowEditor
              workflowId={workflow.id}
              document={document}
              suggestions={current ? suggestions : []}
              halonChanges={halonChanges}
              stepKinds={stepKinds}
              triggerKinds={triggerKinds}
              tools={tools}
              workflows={otherWorkflows}
              timeZones={timeZones}
              editable={editable}
              selection={selection}
              send={send}
              onSelect={setSelection}
            />
          ) : view === VIEWS.VERSIONS ? (
            <VersionsView workflowId={workflow.id} versions={versions} onOpen={openVersion} />
          ) : (
            <SettingsView workflow={workflow} teams={teams} />
          )}
        </div>
      </CanvasActionsContext>
    </AuthenticatedLayout>
  )
}
