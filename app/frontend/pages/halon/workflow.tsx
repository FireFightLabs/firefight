import { Head, usePage, usePoll } from "@inertiajs/react"
import { IconFlask, IconSparkles } from "@tabler/icons-react"
import { useEffect, useState } from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Button } from "@/components/ui/button"
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { useIsMobile } from "@/hooks/use-mobile"
import { WORKFLOW_RUN_OPEN_STATUSES } from "@/lib/generated/constants"
import { CanvasHeader } from "@/pages/halon/components/workflow/canvas-header"
import { HalonChatPanel } from "@/pages/halon/components/workflow/halon-chat-panel"
import { PublishRequestsNotice } from "@/pages/halon/components/workflow/publish-requests-notice"
import { RunsView } from "@/pages/halon/components/workflow/runs-view"
import { SettingsView } from "@/pages/halon/components/workflow/settings-view"
import { SuggestionsBanner } from "@/pages/halon/components/workflow/suggestions-banner"
import { TestRunDialog } from "@/pages/halon/components/workflow/test-run-dialog"
import { VersionActions } from "@/pages/halon/components/workflow/version-actions"
import { VersionsView } from "@/pages/halon/components/workflow/versions-view"
import { WorkflowAlerts } from "@/pages/halon/components/workflow/workflow-alerts"
import { WorkflowControls } from "@/pages/halon/components/workflow/workflow-controls"
import { WorkflowEditor } from "@/pages/halon/components/workflow/workflow-editor"
import { useCanvasActionsValue } from "@/pages/halon/hooks/use-canvas-actions-value"
import { useCanvasView } from "@/pages/halon/hooks/use-canvas-view"
import { useVisitInFlight } from "@/pages/halon/hooks/use-visit-in-flight"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"
import { CANVAS_VISIT, RUN_VISIT, useWorkflowEdits } from "@/pages/halon/hooks/use-workflow-edits"
import { CanvasActionsContext } from "@/pages/halon/lib/workflow/canvas-actions"
import { type Selection, VIEWS, type WorkflowPageProps } from "@/pages/halon/lib/workflow/types"

// Someone else's change, a suggestion of Halon's or a run moving on shows on the canvas within this long.
const REFRESH_EVERY_MS = 5000
const OPEN_RUN: readonly string[] = WORKFLOW_RUN_OPEN_STATUSES

export default function WorkflowCanvasPage() {
  const { workflow, document, versions, suggestions, halonChanges, stepKinds, triggerKinds, tools, publishRequests, otherWorkflows, timeZones, teams,
    myPublishRequest, runs, run, lastRun, chat, chatMessages, chatWaiting, chatUnavailable } = usePage<WorkflowPageProps>().props
  const access = useWorkflowAccess()
  const isMobile = useIsMobile()
  const [ chatOpen, setChatOpen ] = useState(false)
  const [ selection, setSelection ] = useState<Selection>(null)
  const [ trying, setTrying ] = useState<{ upTo: { id: string; title: string } | null } | null>(null)
  const { view, show, openVersion, openRun, leave } = useCanvasView(workflow.id)
  const send = useWorkflowEdits(workflow.id, document)
  const actions = useCanvasActionsValue(workflow.id, send, setSelection)
  const editable = access.build && document.editable
  const current = document.editable
  const runGoing = run !== null && OPEN_RUN.includes(run.status)
  const visitInFlight = useVisitInFlight()
  const { start, stop } = usePoll(REFRESH_EVERY_MS, { only: runGoing ? RUN_VISIT.only : CANVAS_VISIT.only, onBefore: () => !visitInFlight.current },
    { autoStart: false })

  useEffect(() => {
    start()
    return stop
  }, [ start, stop, runGoing ])

  function tryWorkflow() {
    setTrying({ upTo: null })
  }

  function tryStep(stepId: string) {
    const step = document.steps.find((each) => each.id === stepId)
    setTrying({ upTo: step ? { id: step.id, title: step.title } : null })
  }

  function toggleChat() {
    setChatOpen((open) => !open)
  }

  function closeChat() {
    setChatOpen(false)
  }

  function closeTrying(open: boolean) {
    if (!open) {
      setTrying(null)
    }
  }

  const askHalon = (
    <Button type="button" variant="outline" size="sm" aria-pressed={chatOpen} onClick={toggleChat}>
      <IconSparkles className="size-4 text-halon" />
      Ask Halon
    </Button>
  )

  const chatPanel = (
    <HalonChatPanel
      workflowId={workflow.id}
      chat={chat}
      messages={chatMessages}
      waiting={chatWaiting}
      unavailable={chatUnavailable}
      onClose={closeChat}
    />
  )

  const headerActions = run ? (
    <>
      {askHalon}
      <Button type="button" variant="outline" size="sm" onClick={leave}>Back to the editor</Button>
    </>
  ) : (
    <>
      {askHalon}
      <WorkflowControls workflow={workflow} />
      {access.build && document.saved && document.editable && (
        <Button type="button" variant="outline" size="sm" onClick={tryWorkflow}>
          <IconFlask className="size-4" />
          Test run
        </Button>
      )}
      <VersionActions workflow={workflow} document={document} myPublishRequest={myPublishRequest} onLeaveVersion={leave} />
    </>
  )

  return (
    <AuthenticatedLayout title="Workflow" sidebarCollapsed>
      <Head title={`${workflow.name} — Workflow`} />
      <CanvasActionsContext value={actions}>
        <div className="-mt-6 flex h-[calc(100dvh-var(--header-height))] flex-col overflow-hidden">
          <CanvasHeader
            workflow={workflow}
            document={document}
            suggestionCount={current ? suggestions.length : 0}
            run={run}
            view={view}
            onView={show}
            actions={headerActions}
          />
          <WorkflowAlerts workflow={workflow} />
          {access.manage && current && publishRequests.length > 0 && <PublishRequestsNotice requests={publishRequests} />}
          {view === VIEWS.EDITOR && current && suggestions.length > 0 && <SuggestionsBanner workflowId={workflow.id} suggestions={suggestions} />}
          <div className="flex min-h-0 flex-1">
            <div className="flex min-h-0 min-w-0 flex-1 flex-col">
              {view === VIEWS.EDITOR && (
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
                  run={run}
                  lastRun={lastRun}
                  hasDraft={workflow.draftNumber != null}
                  selection={selection}
                  send={send}
                  onSelect={setSelection}
                  onTry={tryStep}
                />
              )}
              {view === VIEWS.RUNS && <RunsView runs={runs} onOpen={openRun} />}
              {view === VIEWS.VERSIONS && <VersionsView workflowId={workflow.id} versions={versions} onOpen={openVersion} />}
              {view === VIEWS.SETTINGS && <SettingsView workflow={workflow} teams={teams} />}
            </div>
            {chatOpen && !isMobile && <aside aria-label="Halon" className="w-[22rem] shrink-0 border-l border-border">{chatPanel}</aside>}
          </div>
        </div>
        {isMobile && (
          <Sheet open={chatOpen} onOpenChange={setChatOpen}>
            <SheetContent side="bottom" className="h-[85dvh] gap-0 p-0 [&>button]:hidden">
              <SheetHeader className="sr-only">
                <SheetTitle>Halon</SheetTitle>
                <SheetDescription>Ask Halon about this workflow.</SheetDescription>
              </SheetHeader>
              {chatPanel}
            </SheetContent>
          </Sheet>
        )}
        {trying && (
          <TestRunDialog open workflowId={workflow.id} document={document} runs={runs} upTo={trying.upTo} onOpenChange={closeTrying} />
        )}
      </CanvasActionsContext>
    </AuthenticatedLayout>
  )
}
