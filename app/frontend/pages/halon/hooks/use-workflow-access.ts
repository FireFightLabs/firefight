import { usePage } from "@inertiajs/react"

import type { WorkflowAccess, WorkflowPageProps } from "@/pages/halon/lib/workflow/types"

// What the person may do on the canvas, as the server read it from the gateway. Building a draft is workflows.create,
// which members hold without a grant, so the app's shared useCan, which answers only for changes, cannot say it.
export function useWorkflowAccess(): WorkflowAccess {
  return usePage<WorkflowPageProps>().props.workflowAccess
}
