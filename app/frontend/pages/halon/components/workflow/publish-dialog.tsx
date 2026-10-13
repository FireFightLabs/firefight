import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { whenClosed } from "@/lib/handlers"
import type { WorkflowDetail, WorkflowDocument } from "@/types/serializers"

interface PublishDialogProps {
  open: boolean
  workflow: WorkflowDetail
  document: WorkflowDocument
  onPublish: () => void
  onOpenChange: (open: boolean) => void
}

function lowerFirst(words: string): string {
  return words.charAt(0).toLowerCase() + words.slice(1)
}

// Publishing asks first: what changes for runs, what the workflow's own identity is granted for its steps, and what stops
// the draft going live when something does.
export function PublishDialog({ open, workflow, document, onPublish, onOpenChange }: PublishDialogProps) {
  const replaces = workflow.liveNumber ? `It replaces version ${workflow.liveNumber}, and runs already going finish on the version they started on.` : "It is the first version to go live."
  const runs = workflow.shownTriggerWords ? ` It runs ${lowerFirst(workflow.shownTriggerWords)}.` : ""
  const missing = workflow.reach.filter((need) => !need.held)

  function close() {
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(close)}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Publish {workflow.name} version {document.number}?</DialogTitle>
          <DialogDescription>Every run starts on it from now on. {replaces}{runs}</DialogDescription>
        </DialogHeader>
        {missing.length > 0 ? (
          <div className="space-y-1.5">
            <p className="text-sm text-fg-primary">Publishing also lets it do the following, granted to the workflow alone in every environment.</p>
            <ul className="list-disc space-y-1 pl-5 text-sm">
              {missing.map((need) => <li key={need.key}>{need.label}</li>)}
            </ul>
          </div>
        ) : (
          <p className="text-sm text-fg-secondary">It already holds everything its steps need, so nothing new is granted.</p>
        )}
        {document.problems.length > 0 && (
          <div className="space-y-1.5 rounded-md border border-error-border bg-error-tint p-3">
            <p className="text-sm font-medium text-error">It cannot be published yet.</p>
            <ul className="list-disc space-y-1 pl-4 text-xs text-fg-primary">
              {document.problems.map((problem) => <li key={problem}>{problem}</li>)}
            </ul>
          </div>
        )}
        <DialogFooter>
          <Button type="button" variant="outline" onClick={close}>Cancel</Button>
          <Button type="button" disabled={document.problems.length > 0} onClick={onPublish}>Publish</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
