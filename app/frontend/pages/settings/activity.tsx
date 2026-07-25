import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ActivityTab } from "@/pages/settings/components/activity/activity-tab"
import type { AbilityInvocation } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface ActivityPageProps extends SharedProps {
  [key: string]: unknown
  invocations: AbilityInvocation[]
  decision: string | null
}

export default function Activity() {
  const { invocations, decision } = usePage<ActivityPageProps>().props

  return (
    <AuthenticatedLayout title="Activity">
      <Head title="Activity" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <ActivityTab invocations={invocations} decision={decision} />
      </div>
    </AuthenticatedLayout>
  )
}
