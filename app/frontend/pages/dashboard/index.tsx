import { Head } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { StatCards } from "@/modules/dashboard/components/stat-cards"
import { IncidentsTable } from "@/modules/dashboard/components/incidents-table"

export default function Dashboard() {
  return (
    <AuthenticatedLayout title="Dashboard">
      <Head title="Dashboard" />
      <div className="flex flex-col gap-4 py-4 md:gap-6 md:py-6">
        <StatCards />
        <IncidentsTable />
      </div>
    </AuthenticatedLayout>
  )
}
