import { VersionRow } from "@/pages/halon/components/workflow/version-row"
import type { WorkflowVersionRow } from "@/types/serializers"

// Every version of the workflow, newest first, each with who changed what. Any one opens on the canvas, and an older one
// is restored as a new draft.
export function VersionsView({ workflowId, versions, onOpen }: { workflowId: string; versions: WorkflowVersionRow[]; onOpen: (versionId: string) => void }) {
  return (
    <div className="h-full overflow-y-auto px-4 py-5">
      <div className="mx-auto max-w-3xl space-y-3">
        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
          <h2 className="text-base font-semibold text-fg-headline">Versions</h2>
          <p className="text-[12.5px] text-fg-muted">Any version can be opened, and an older one restored as a new draft.</p>
        </div>
        {versions.length === 0 ? (
          <p className="border border-border bg-surface-card px-4 py-6 text-center text-sm text-fg-muted">Nothing is saved yet. The first change on the canvas starts version 1.</p>
        ) : (
          <ol className="space-y-2">
            {versions.map((version) => <VersionRow key={version.id} workflowId={workflowId} version={version} onOpen={onOpen} />)}
          </ol>
        )}
      </div>
    </div>
  )
}
