import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { RunbooksTab } from "@/pages/settings/components/runbooks/runbooks-tab"
import type {
  IncidentSeveritySettings,
  IncidentTypeSettings,
  RunbookSettings,
} from "@/types/serializers"
import type { SharedProps } from "@/types"

interface RunbooksPageProps extends SharedProps {
  [key: string]: unknown
  runbooks: RunbookSettings[]
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
}

export default function Runbooks() {
  const { runbooks, incidentTypes, severities } = usePage<RunbooksPageProps>().props

  return (
    <AuthenticatedLayout title="Runbooks">
      <Head title="Runbooks" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <RunbooksTab
          runbooks={runbooks}
          incidentTypes={incidentTypes}
          severities={severities}
        />
      </div>
    </AuthenticatedLayout>
  )
}
