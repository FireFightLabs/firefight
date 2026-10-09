import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { useCan } from "@/lib/permissions"
import { AlertSourcesTab } from "@/pages/settings/components/alert-sources/alert-sources-tab"
import type { AlertSourceSettings, IncidentSeveritySettings } from "@/types/serializers"
import type { SharedProps } from "@/types"
import type { SetupInstructions } from "@/pages/settings/lib/alerts"

interface AlertSourcesPageProps extends SharedProps {
  [key: string]: unknown
  alertSources: AlertSourceSettings[]
  severities: IncidentSeveritySettings[]
  setupInstructions: SetupInstructions
}

export default function AlertSources() {
  const { alertSources, severities, setupInstructions } = usePage<AlertSourcesPageProps>().props
  const canManage = useCan("alerts")

  return (
    <AuthenticatedLayout title="Alert Sources">
      <Head title="Alert Sources" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <AlertSourcesTab
          alertSources={alertSources}
          severities={severities}
          setupInstructions={setupInstructions}
          canManage={canManage}
        />
      </div>
    </AuthenticatedLayout>
  )
}
