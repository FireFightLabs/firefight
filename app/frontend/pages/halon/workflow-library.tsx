import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { useCan } from "@/lib/permissions"
import type { SharedProps } from "@/types"
import type { HalonLibraryWorkflow, HalonLibraryWorkflowUse } from "@/types/serializers"
import { LibraryItemsCard } from "@/pages/halon/components/workflow-library/library-items-card"
import { WorkflowsCard } from "@/pages/halon/components/workflow-library/workflows-card"

interface WorkflowLibraryPageProps extends SharedProps {
  items: HalonLibraryWorkflow[]
  workflows: HalonLibraryWorkflowUse[]
}

export default function HalonWorkflowLibraryPage() {
  const { items, workflows } = usePage<WorkflowLibraryPageProps>().props
  const canManage = useCan("workflows")

  return (
    <AuthenticatedLayout title="Workflow library">
      <Head title="Workflow library" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <p className="max-w-prose text-sm text-fg-secondary">
          A workflow is a trigger and the steps that follow it, run without anyone asking. Start from one Firefight ships, or bring
          in one a team exported elsewhere.
        </p>
        <WorkflowsCard workflows={workflows} canManage={canManage} />
        <LibraryItemsCard items={items} canManage={canManage} />
      </div>
    </AuthenticatedLayout>
  )
}
