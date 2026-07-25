import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ApprovalsTab } from "@/pages/settings/components/approvals/approvals-tab"
import type { AbilityApproval } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface ApprovalsPageProps extends SharedProps {
  [key: string]: unknown
  pendingApprovals: AbilityApproval[]
  resolvedApprovals: AbilityApproval[]
}

export default function Approvals() {
  const { pendingApprovals, resolvedApprovals } = usePage<ApprovalsPageProps>().props

  return (
    <AuthenticatedLayout title="Approvals">
      <Head title="Approvals" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <ApprovalsTab pendingApprovals={pendingApprovals} resolvedApprovals={resolvedApprovals} />
      </div>
    </AuthenticatedLayout>
  )
}
