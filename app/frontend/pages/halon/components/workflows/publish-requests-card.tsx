import { Link, router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { dismissWorkflowPublishRequestPath, publishWorkflowPublishRequestPath, workflowPath } from "@/lib/routes"
import { timeAgo } from "@/lib/time"
import type { WorkflowPublishRequest } from "@/types/serializers"

function publish(request: WorkflowPublishRequest) {
  router.post(publishWorkflowPublishRequestPath(request.id), {}, { preserveScroll: true })
}

function dismiss(request: WorkflowPublishRequest) {
  router.post(dismissWorkflowPublishRequestPath(request.id), {}, { preserveScroll: true })
}

function grantWords(request: WorkflowPublishRequest): string {
  if (request.wouldGrant.length === 0) {
    return "Publishing grants it nothing new."
  }
  return `Publishing also lets it ${request.wouldGrant.map((label) => label.charAt(0).toLowerCase() + label.slice(1)).join(", ")}.`
}

// What members asked an admin to publish, shown to the admins who can.
export function PublishRequestsCard({ requests }: { requests: WorkflowPublishRequest[] }) {
  return (
    <Card className="border-warning-border">
      <CardHeader>
        <CardTitle>Waiting to be published</CardTitle>
        <CardDescription className="mt-1">Members built these and asked an admin to publish them.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col divide-y">
        {requests.map((request) => (
          <div key={request.id} className="flex flex-col gap-3 py-3 first:pt-0 last:pb-0 sm:flex-row sm:items-center sm:justify-between">
            <div className="min-w-0 text-sm">
              <Link href={workflowPath(request.workflowId)} className="font-medium hover:underline">{request.workflowName}</Link>
              <p className="text-muted-foreground">
                {request.requesterName} asked{request.requestedAt && ` ${timeAgo(request.requestedAt)}`}. {grantWords(request)}
              </p>
            </div>
            <div className="flex shrink-0 gap-2">
              <Button size="sm" variant="outline" onClick={() => dismiss(request)}>Dismiss</Button>
              <Button size="sm" onClick={() => publish(request)}>Publish</Button>
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}
