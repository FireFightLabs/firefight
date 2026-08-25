import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { useCan } from "@/lib/permissions"
import { AlertSourcesTab } from "@/pages/settings/components/alert-sources/alert-sources-tab"
import type { AlertSourceSettings, IncidentSeveritySettings } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface AlertSourcesPageProps extends SharedProps {
  [key: string]: unknown
  alertSources: AlertSourceSettings[]
  severities: IncidentSeveritySettings[]
}

export default function AlertSources() {
  const { alertSources, severities } = usePage<AlertSourcesPageProps>().props
  const canManage = useCan("alerts")

  return (
    <AuthenticatedLayout title="Alert Sources">
      <Head title="Alert Sources" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <AlertSourcesTab alertSources={alertSources} severities={severities} canManage={canManage} />
      </div>
    </AuthenticatedLayout>
  )
}
