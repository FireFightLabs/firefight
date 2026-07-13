import { Head, Link, usePage } from "@inertiajs/react"
import { IconArrowLeft } from "@tabler/icons-react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { settingsAlertSourcesPath } from "@/lib/routes"
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
  const prefillSource = new URLSearchParams(window.location.search).get("source")

  return (
    <AuthenticatedLayout title="Alert Routing">
      <Head title="Alert Routing" />
      <div className="flex flex-col gap-4 px-4 py-4 md:py-6 lg:px-6">
        <Link
          href={settingsAlertSourcesPath()}
          className="flex items-center gap-1.5 text-[12px] text-muted-foreground/80 transition-colors hover:text-foreground"
        >
          <IconArrowLeft className="size-3.5" />
          Alert Sources
        </Link>
        <AlertRoutingTab policy={policy} severities={severities} prefillSource={prefillSource} />
      </div>
    </AuthenticatedLayout>
  )
}
