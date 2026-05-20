import { Deferred, Head, usePage } from "@inertiajs/react"

import type { Pagination, SharedProps } from "@/types"
import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { StatCards, StatCardsSkeleton } from "@/modules/dashboard/components/stat-cards"
import { IncidentsTable } from "@/modules/dashboard/components/incidents-table"
import type { DashboardStat, DashboardFilters } from "@/modules/dashboard/types"
import type { IncidentListItem, SeverityOption } from "@/types/serializers"

interface DashboardPageProps extends SharedProps {
  stats?: DashboardStat[]
  incidents: IncidentListItem[]
  pagination: Pagination
  filters: DashboardFilters
  severityOptions: SeverityOption[]
}

export default function Dashboard() {
  const { stats, incidents, pagination, filters, severityOptions } = usePage<DashboardPageProps>().props

  return (
    <AuthenticatedLayout title="Incidents">
      <Head title="Incidents" />
      <div className="flex flex-col gap-6 py-4 md:gap-8 md:py-6">
        <Deferred data="stats" fallback={<StatCardsSkeleton />}>
          <StatCards stats={stats ?? []} />
        </Deferred>
        <IncidentsTable
          incidents={incidents}
          pagination={pagination}
          filters={filters}
          severityOptions={severityOptions}
        />
      </div>
    </AuthenticatedLayout>
  )
}
