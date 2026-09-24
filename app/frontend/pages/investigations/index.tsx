import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { InvestigationsTable } from "@/pages/investigations/components/investigations-table"
import type { InvestigationsPageProps } from "@/pages/investigations/types"

export default function Investigations() {
  const { investigations, pagination, incident } = usePage<InvestigationsPageProps>().props

  return (
    <AuthenticatedLayout title="Investigations">
      <Head title="Investigations" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <InvestigationsTable investigations={investigations} pagination={pagination} incident={incident} />
      </div>
    </AuthenticatedLayout>
  )
}
