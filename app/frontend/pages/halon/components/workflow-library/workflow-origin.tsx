import { Badge } from "@/components/ui/badge"
import type { HalonLibraryWorkflowUse } from "@/types/serializers"

// Where a workflow came from: the workspace's own, Firefight's library followed as it is, or a copy with the library
// version it holds and a marker when Firefight shipped a newer one, which opens what changed.
export function WorkflowOrigin({ workflow, onUpdate }: { workflow: HalonLibraryWorkflowUse; onUpdate: () => void }) {
  if (!workflow.fromLibrary) {
    return <span className="text-muted-foreground">Your own</span>
  }
  if (workflow.following) {
    return <span className="text-muted-foreground">Firefight&apos;s {workflow.itemName}, version {workflow.libraryVersion}, kept up to date</span>
  }

  return (
    <div className="flex flex-col items-start gap-1">
      <span className="text-muted-foreground">Your copy of {workflow.itemName ?? "a library workflow"}, version {workflow.libraryVersion}</span>
      {workflow.libraryUpdate && (
        <button type="button" onClick={onUpdate} className="rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand">
          <Badge variant="outline" className="border-warning text-warning">Version {workflow.libraryUpdate.version} is out</Badge>
        </button>
      )}
    </div>
  )
}
