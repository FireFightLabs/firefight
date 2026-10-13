import { Link } from "@inertiajs/react"
import { IconChevronRight, IconSparkles } from "@tabler/icons-react"
import type { ReactNode } from "react"

import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { cn } from "@/lib/utils"
import { WORKFLOW_VERSION_STATUS } from "@/lib/generated/constants"
import { halonWorkflowsPath } from "@/lib/routes"
import { formatWhen } from "@/pages/halon/components/workflows/labels"
import { type CanvasView, VIEWS } from "@/pages/halon/lib/workflow/types"
import type { WorkflowDetail, WorkflowDocument } from "@/types/serializers"

const VIEW_LABELS: Record<CanvasView, string> = { editor: "Editor", versions: "Versions", settings: "Settings" }
const CHIP = "inline-flex h-[22px] items-center gap-1.5 rounded-full border px-2 text-[11px] font-medium whitespace-nowrap"

interface CanvasHeaderProps {
  workflow: WorkflowDetail
  document: WorkflowDocument
  suggestionCount: number
  view: CanvasView
  onView: (view: CanvasView) => void
  // The version's own actions, publish or restore, on the right.
  actions: ReactNode
}

// The canvas's top line: which workflow, which version is shown and whether it is live, how many of Halon's suggestions
// wait, the views, and what can be done with the version.
export function CanvasHeader({ workflow, document, suggestionCount, view, onView, actions }: CanvasHeaderProps) {
  const draft = document.status === WORKFLOW_VERSION_STATUS.DRAFT
  const status = !document.saved
    ? "Not saved yet"
    : draft
      ? `Draft v${document.number}`
      : document.status === WORKFLOW_VERSION_STATUS.LIVE
        ? `Live · v${document.number}`
        : `Version ${document.number}, read only`

  function chooseView(value: string) {
    const next = Object.values(VIEWS).find((each) => each === value)
    if (next) {
      onView(next)
    }
  }

  return (
    <header className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-border px-4 py-2.5">
      <div className="flex min-w-0 items-center gap-1.5 text-[13px] text-fg-muted">
        <Link href={halonWorkflowsPath()} className="hover:text-fg-primary hover:underline">Workflows</Link>
        <IconChevronRight className="size-3 opacity-60" />
        <h1 className="truncate font-medium text-fg-headline">{workflow.name}</h1>
      </div>
      <span className={cn(CHIP, document.status === WORKFLOW_VERSION_STATUS.LIVE && document.saved ? "border-brand-border text-brand" : "border-border-strong text-fg-secondary")}>
        <span className="size-1.5 rounded-full bg-current" />
        {status}
      </span>
      {draft && document.saved && workflow.liveNumber && <span className={cn(CHIP, "border-border text-fg-muted")}>Live is v{workflow.liveNumber}</span>}
      <span className="text-[12px] text-fg-muted">
        {workflow.triggerWords}
        {workflow.enabled && workflow.nextRunAt && `, next ${formatWhen(workflow.nextRunAt)}`}
        {workflow.liveNumber && !workflow.enabled && ", switched off"}
      </span>
      {suggestionCount > 0 && (
        <span className={cn(CHIP, "border-halon-border text-halon")}>
          <IconSparkles className="size-3" />
          {suggestionCount === 1 ? "1 suggestion from Halon" : `${suggestionCount} suggestions from Halon`}
        </span>
      )}
      <div className="grow" />
      <ToggleGroup type="single" variant="outline" size="sm" value={view} onValueChange={chooseView} aria-label="View">
        {Object.values(VIEWS).map((each) => <ToggleGroupItem key={each} value={each} className="px-3 text-xs">{VIEW_LABELS[each]}</ToggleGroupItem>)}
      </ToggleGroup>
      {actions}
    </header>
  )
}
