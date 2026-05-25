import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { SeveritiesTab } from "@/pages/settings/components/severities/severities-tab"
import type { IncidentSeveritySettings } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface SeveritiesPageProps extends SharedProps {
  [key: string]: unknown
  severities: IncidentSeveritySettings[]
}

export default function Severities() {
  const { severities } = usePage<SeveritiesPageProps>().props

  return (
    <AuthenticatedLayout title="Severities">
      <Head title="Severities" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <SeveritiesTab severities={severities} />
      </div>
    </AuthenticatedLayout>
  )
}
