import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { useCan } from "@/lib/permissions"
import { RunbooksTab } from "@/pages/settings/components/runbooks/runbooks-tab"
import type {
  IncidentSeveritySettings,
  IncidentTypeSettings,
  RunbookCustomField,
  RunbookSettings,
} from "@/types/serializers"
import type { SharedProps } from "@/types"

interface RunbooksPageProps extends SharedProps {
  [key: string]: unknown
  runbooks: RunbookSettings[]
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  customFields: RunbookCustomField[]
}

export default function Runbooks() {
  const { runbooks, incidentTypes, severities, customFields } = usePage<RunbooksPageProps>().props
  const canManage = useCan("runbooks")

  return (
    <AuthenticatedLayout title="Runbooks">
      <Head title="Runbooks" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <RunbooksTab
          runbooks={runbooks}
          incidentTypes={incidentTypes}
          severities={severities}
          customFields={customFields}
          canManage={canManage}
        />
      </div>
    </AuthenticatedLayout>
  )
}
