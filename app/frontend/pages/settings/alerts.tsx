import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { RecentAlertsTab } from "@/pages/settings/components/alerts/recent-alerts-tab"
import type { AlertSettings } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface AlertsPageProps extends SharedProps {
  [key: string]: unknown
  alerts: AlertSettings[]
  alertSources: { id: string; name: string }[]
  sourceId: string | null
}

export default function Alerts() {
  const { alerts, alertSources, sourceId } = usePage<AlertsPageProps>().props

  return (
    <AuthenticatedLayout title="Alerts">
      <Head title="Alerts" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <RecentAlertsTab alerts={alerts} alertSources={alertSources} sourceId={sourceId} />
      </div>
    </AuthenticatedLayout>
  )
}
