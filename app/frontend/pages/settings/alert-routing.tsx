import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { AlertRoutingTab } from "@/pages/settings/components/alert-routing/alert-routing-tab"
import type { AlertRoutingPolicy, IncidentSeveritySettings } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface AlertRoutingPageProps extends SharedProps {
  [key: string]: unknown
  policy: AlertRoutingPolicy | null
  severities: IncidentSeveritySettings[]
}

export default function AlertRouting() {
  const { policy, severities } = usePage<AlertRoutingPageProps>().props

  return (
    <AuthenticatedLayout title="Alert Routing">
      <Head title="Alert Routing" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <AlertRoutingTab policy={policy} severities={severities} />
      </div>
    </AuthenticatedLayout>
  )
}
