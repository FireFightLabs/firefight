import { router } from "@inertiajs/react"
import { IconArrowUp } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { formatDateTime } from "@/lib/formatters"
import { dismissWorkflowPublishRequestPath } from "@/lib/routes"
import { CANVAS_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import type { WorkflowPublishRequest } from "@/types/serializers"

function askedWords(request: WorkflowPublishRequest): string {
  const when = request.requestedAt ? ` on ${formatDateTime(request.requestedAt)}` : ""
  return `${request.requesterName} asked${when} for this draft to be published.`
}

// For someone who may publish: the members waiting for the draft to go live. Publishing answers them all, and Dismiss
// answers one, and each is told either way.
export function PublishRequestsNotice({ requests }: { requests: WorkflowPublishRequest[] }) {
  function dismiss(requestId: string) {
    return () => router.post(dismissWorkflowPublishRequestPath(requestId), {}, CANVAS_VISIT)
  }

  return (
    <div className="space-y-1.5 border-b border-border bg-surface-card px-4 py-2 edge-bar">
      {requests.map((request) => (
        <div key={request.id} className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
          <IconArrowUp className="size-4 shrink-0 text-brand" />
          <p className="min-w-0 flex-1 text-[13px] text-fg-primary">{askedWords(request)}</p>
          {request.wouldGrant.length > 0 && (
            <p className="w-full pl-7 text-xs text-fg-muted">Publishing grants it {request.wouldGrant.join(", ")}.</p>
          )}
          <Button type="button" size="sm" variant="outline" className="h-7 text-xs" onClick={dismiss(request.id)}>Dismiss</Button>
        </div>
      ))}
    </div>
  )
}
