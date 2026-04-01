import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { StatusesTab } from "@/modules/settings/components/statuses-tab"
import type { LifecycleStageWithStatuses } from "@/modules/settings/types"
import type { SharedProps } from "@/types"

interface StatusesPageProps extends SharedProps {
  [key: string]: unknown
  lifecycleStages: LifecycleStageWithStatuses[]
}

export default function Statuses() {
  const { lifecycleStages } = usePage<StatusesPageProps>().props

  return (
    <AuthenticatedLayout title="Statuses">
      <Head title="Statuses" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <StatusesTab lifecycleStages={lifecycleStages} />
      </div>
    </AuthenticatedLayout>
  )
}
