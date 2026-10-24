import { ReactFlowProvider } from "@xyflow/react"
import { IconHistory, IconPlus } from "@tabler/icons-react"
import { useCallback, useMemo, useState } from "react"

import { Button } from "@/components/ui/button"
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { useIsMobile } from "@/hooks/use-mobile"
import { cn } from "@/lib/utils"
import { WORKFLOW_EDIT_OPERATIONS, WORKFLOW_TRIGGER_KEYS } from "@/lib/generated/constants"
import { jsonValue } from "@/lib/tool-fields"
import { CanvasToolbar } from "@/pages/halon/components/workflow/canvas-toolbar"
import { FlowCanvas } from "@/pages/halon/components/workflow/flow-canvas"
import { HalonChangesPanel } from "@/pages/halon/components/workflow/halon-changes-panel"
import { Inspector } from "@/pages/halon/components/workflow/inspector"
import { RunStepPanel } from "@/pages/halon/components/workflow/run-step-panel"
import { RunSummary } from "@/pages/halon/components/workflow/run-summary"
import { StepList } from "@/pages/halon/components/workflow/step-list"
import { StepPalette } from "@/pages/halon/components/workflow/step-palette"
import { type AddAt, useAddStep } from "@/pages/halon/hooks/use-add-step"
import type { SendEdit } from "@/pages/halon/hooks/use-workflow-edits"
import { startingTrigger } from "@/pages/halon/lib/schedule"
import type { PaletteChoice } from "@/pages/halon/lib/workflow/new-step"
import { stepStates } from "@/pages/halon/lib/workflow/run-states"
import type { OtherWorkflow, Selection } from "@/pages/halon/lib/workflow/types"
import type {
  WorkflowDocument,
  WorkflowHalonChange,
  WorkflowRunDetail,
  WorkflowRunStates,
  WorkflowStepKind,
  WorkflowSuggestion,
  WorkflowToolChoice,
  WorkflowTriggerKind,
} from "@/types/serializers"

interface WorkflowEditorProps {
  workflowId: string
  document: WorkflowDocument
  suggestions: WorkflowSuggestion[]
  halonChanges: WorkflowHalonChange[]
  stepKinds: WorkflowStepKind[]
  triggerKinds: WorkflowTriggerKind[]
  tools: WorkflowToolChoice[] | undefined
  workflows: OtherWorkflow[]
  timeZones: string[]
  editable: boolean
  // The run shown on the canvas, when the address names one.
  run: WorkflowRunDetail | null
  lastRun: WorkflowRunStates | null
  // There is a draft whose steps an output can be pinned on.
  hasDraft: boolean
  selection: Selection
  send: SendEdit
  onSelect: (selection: Selection) => void
  onTry: (stepId: string) => void
}

// The editor: the palette docked on the left, the canvas in the middle and the settings of what is selected docked on
// the right. Narrower, the palette opens over the canvas from Add a step, and on a phone the canvas is a list of the
// steps in order, each opening its settings over the page. A run shown on the canvas draws each step's state, and the
// panel on the right is that run's instead.
export function WorkflowEditor(props: WorkflowEditorProps) {
  const { workflowId, document, suggestions, halonChanges, stepKinds, triggerKinds, tools, workflows, timeZones, editable, run, lastRun, hasDraft, selection,
    send, onSelect, onTry } = props
  const isMobile = useIsMobile()
  const [ highlightHalon, setHighlightHalon ] = useState(false)
  const [ showLastRun, setShowLastRun ] = useState(false)
  const [ paletteOpen, setPaletteOpen ] = useState(false)
  const selectedId = selection?.kind === "step" ? selection.id : null
  const states = useMemo(() => {
    if (run) {
      return stepStates(run.steps)
    }
    return showLastRun && lastRun ? stepStates(lastRun.steps) : undefined
  }, [ run, lastRun, showLastRun ])

  const opened = useCallback((stepId: string) => onSelect({ kind: "step", id: stepId }), [ onSelect ])
  const addStep = useAddStep(document, send, selectedId, opened)

  const addFromPalette = useCallback((choice: PaletteChoice, at?: AddAt) => {
    setPaletteOpen(false)
    addStep(choice, at)
  }, [ addStep ])

  function chooseTrigger(kind: WorkflowTriggerKind) {
    setPaletteOpen(false)
    const trigger = { ...startingTrigger(kind), [WORKFLOW_TRIGGER_KEYS.KIND]: kind.key, [WORKFLOW_TRIGGER_KEYS.INPUTS]: jsonValue(document.trigger.inputs) }
    send(WORKFLOW_EDIT_OPERATIONS.CHANGE_TRIGGER, { trigger }, { onSuccess: () => onSelect({ kind: "trigger" }) })
  }

  function openPalette() {
    setPaletteOpen(true)
  }

  function toggleLastRun() {
    setShowLastRun(!showLastRun)
  }

  function backToRun() {
    onSelect(null)
  }

  function closeSide(open: boolean) {
    if (!open) {
      onSelect(null)
    }
  }

  const selectedStep = selectedId ? document.steps.find((step) => step.id === selectedId) ?? null : null
  const palette = (
    <StepPalette
      stepKinds={stepKinds}
      triggerKinds={triggerKinds}
      tools={tools}
      triggerKind={document.trigger.kind}
      disabled={!editable}
      onAddStep={addFromPalette}
      onChooseTrigger={chooseTrigger}
    />
  )
  const runPanel = run && (selectedStep
    ? <RunStepPanel key={selectedStep.id} workflowId={workflowId} run={run} step={selectedStep} canPin={hasDraft} onBack={backToRun} />
    : <RunSummary workflowId={workflowId} run={run} steps={document.steps} onPick={opened} />)
  const side = runPanel ?? (
    <Inspector
      workflowId={workflowId}
      document={document}
      suggestions={suggestions}
      selection={selection}
      stepKinds={stepKinds}
      triggerKinds={triggerKinds}
      tools={tools}
      workflows={workflows}
      timeZones={timeZones}
      editable={editable}
      send={send}
      onSelect={onSelect}
      onTry={onTry}
    />
  )

  return (
    <div className={cn("grid min-h-0 flex-1 grid-cols-1 md:grid-cols-[minmax(0,1fr)_19rem]", !run && "lg:grid-cols-[15.5rem_minmax(0,1fr)_19rem]")}>
      {!run && <aside aria-label="Add a step" className="hidden min-h-0 border-r border-border lg:block">{palette}</aside>}
      <div className="relative min-h-0 overflow-hidden">
        {isMobile ? (
          <div className="h-full overflow-y-auto pb-20">
            <StepList document={document} suggestions={suggestions} highlightHalon={highlightHalon} states={states} onSelect={onSelect} />
          </div>
        ) : (
          <ReactFlowProvider>
            <FlowCanvas
              document={document}
              suggestions={suggestions}
              stepKinds={stepKinds}
              tools={tools ?? []}
              highlightHalon={highlightHalon}
              selection={selection}
              readOnly={!editable}
              states={states}
              send={send}
              onSelect={onSelect}
              onAdd={addFromPalette}
            />
            <div className="absolute top-3 right-3 z-10">
              <CanvasToolbar highlightHalon={highlightHalon} onHighlightHalon={setHighlightHalon}>
                {!run && lastRun && (
                  <button
                    type="button"
                    aria-pressed={showLastRun}
                    onClick={toggleLastRun}
                    className={cn("flex h-7 items-center gap-1.5 rounded-sm px-2 text-[11.5px] hover:bg-surface-hover", showLastRun ? "text-brand" : "text-fg-secondary")}
                  >
                    <IconHistory className="size-3.5" />
                    Last run
                  </button>
                )}
              </CanvasToolbar>
            </div>
            {highlightHalon && (
              <div className="absolute top-14 right-3 z-10">
                <HalonChangesPanel workflowId={workflowId} changes={halonChanges} />
              </div>
            )}
          </ReactFlowProvider>
        )}
        {editable && !run && (
          <div className="absolute bottom-4 left-4 z-10 lg:hidden">
            <Button type="button" size="sm" onClick={openPalette}>
              <IconPlus className="size-4" />
              Add a step
            </Button>
          </div>
        )}
      </div>
      {!isMobile && <aside aria-label={run ? "Run" : "Step settings"} className="min-h-0 border-l border-border">{side}</aside>}
      <Sheet open={paletteOpen} onOpenChange={setPaletteOpen}>
        <SheetContent side={isMobile ? "bottom" : "left"} className="h-[80dvh] gap-0 p-0 md:h-full">
          <SheetHeader className="sr-only">
            <SheetTitle>Add a step</SheetTitle>
            <SheetDescription>Pick a step to add below the one selected.</SheetDescription>
          </SheetHeader>
          {palette}
        </SheetContent>
      </Sheet>
      {isMobile && (
        <Sheet open={selection !== null} onOpenChange={closeSide}>
          <SheetContent side="bottom" className="h-[85dvh] gap-0 p-0">
            <SheetHeader className="sr-only">
              <SheetTitle>{run ? "Step in this run" : "Settings"}</SheetTitle>
              <SheetDescription>{run ? "What the step did in this run." : "What the selected step or the trigger does."}</SheetDescription>
            </SheetHeader>
            {side}
          </SheetContent>
        </Sheet>
      )}
    </div>
  )
}
