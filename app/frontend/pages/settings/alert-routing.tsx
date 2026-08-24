import { Head, Link, usePage } from "@inertiajs/react"
import { IconAlertTriangle } from "@tabler/icons-react"

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { IconArrowLeft } from "@tabler/icons-react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { settingsAlertSourcesPath } from "@/lib/routes"
import { AlertRoutingTab } from "@/pages/settings/components/alert-routing/alert-routing-tab"
import type { AlertRoutingPolicy, IncidentSeveritySettings, WorkspaceMembership } from "@/types/serializers"
import type { SlackChannel } from "@/types"
import type { CatalogOptionMap } from "@/pages/settings/lib/alerts"
import type { SharedProps } from "@/types"

interface AlertRoutingPageProps extends SharedProps {
  [key: string]: unknown
  policy: AlertRoutingPolicy | null
  alertSource: { id: string; name: string } | null
  hasWorkspaceFallback: boolean
  severities: IncidentSeveritySettings[]
  channels: SlackChannel[]
  members: WorkspaceMembership[]
  catalogOptions: CatalogOptionMap
  roleWarnings: string[]
}

export default function AlertRouting() {
  const { policy, alertSource, hasWorkspaceFallback, severities, channels, members, catalogOptions, roleWarnings } = usePage<AlertRoutingPageProps>().props

  return (
    <AuthenticatedLayout title="Alert Routing">
      <Head title={alertSource ? `Alert Routing - ${alertSource.name}` : "Alert Routing"} />
      <div className="flex flex-col gap-4 px-4 py-4 md:py-6 lg:px-6">
        <Link
          href={settingsAlertSourcesPath()}
          className="flex items-center gap-1.5 text-[12px] text-muted-foreground/80 transition-colors hover:text-foreground"
        >
          <IconArrowLeft className="size-3.5" />
          Alert Sources
        </Link>
        {roleWarnings.length > 0 && (
          <Alert variant="destructive" className="flex items-start gap-3">
            <IconAlertTriangle className="mt-0.5 size-5 shrink-0" />
            <div>
              <AlertTitle>Routing cannot reach its targets</AlertTitle>
              <AlertDescription>
                {roleWarnings.map((warning) => (
                  <p key={warning}>{warning}</p>
                ))}
                <p>Open the type in the Catalogue, edit it, and pick the role on one of its attributes.</p>
              </AlertDescription>
            </div>
          </Alert>
        )}
        <AlertRoutingTab
          policy={policy}
          severities={severities}
          channels={channels}
          members={members}
          catalogOptions={catalogOptions}
          alertSource={alertSource}
          hasWorkspaceFallback={hasWorkspaceFallback}
        />
      </div>
    </AuthenticatedLayout>
  )
}
