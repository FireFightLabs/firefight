import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { StatCards } from "@/modules/dashboard/components/stat-cards"
import { IncidentsTable } from "@/modules/dashboard/components/incidents-table"
import type { DashboardStat } from "@/modules/dashboard/types"
import type { IncidentListItem } from "@/modules/incidents/types"
import { mockStats, mockIncidents } from "@/modules/dashboard/lib/mock-data"

export default function Dashboard() {
  const { stats, incidents } = usePage<{
    stats?: DashboardStat[]
    incidents?: IncidentListItem[]
  }>().props

  return (
    <AuthenticatedLayout title="Incidents">
      <Head title="Incidents" />
      <div className="flex flex-col gap-4 py-4 md:gap-6 md:py-6">
        <StatCards stats={stats ?? mockStats} />
        <IncidentsTable incidents={incidents ?? mockIncidents} />
      </div>
    </AuthenticatedLayout>
  )
}
