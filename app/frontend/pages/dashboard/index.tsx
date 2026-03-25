import { Head } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { SectionCards } from "@/components/section-cards"
import { DataTable } from "@/components/data-table"

export default function Dashboard() {
  return (
    <AuthenticatedLayout title="Dashboard">
      <Head title="Dashboard" />
      <div className="flex flex-col gap-4 py-4 md:gap-6 md:py-6">
        <SectionCards />
        <DataTable />
      </div>
    </AuthenticatedLayout>
  )
}
