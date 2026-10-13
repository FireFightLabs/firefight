import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { whenClosed } from "@/lib/handlers"
import { workflowRunSavedResultPath } from "@/lib/routes"
import { SavedResultText } from "@/pages/halon/components/workflow/saved-result-text"

interface SavedResultDialogProps {
  workflowId: string
  runId: string
  result: { id: string; handle: string } | null
  onClose: () => void
}

// One result a step kept whole, opened from the run's view.
export function SavedResultDialog({ workflowId, runId, result, onClose }: SavedResultDialogProps) {
  return (
    <Dialog open={result !== null} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>{result?.handle}</DialogTitle>
          <DialogDescription>The whole of what the step gave, kept because it was too large to carry in the run.</DialogDescription>
        </DialogHeader>
        {result && <SavedResultText path={workflowRunSavedResultPath(workflowId, runId, result.id)} />}
      </DialogContent>
    </Dialog>
  )
}
