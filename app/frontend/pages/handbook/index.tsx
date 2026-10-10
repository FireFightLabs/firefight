import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { HandbookScreen } from "@/pages/handbook/components/handbook-screen"
import type { HandbookPageProps } from "@/pages/handbook/types"

export default function HandbookIndex() {
  const { pages, suggestions, directingRole, proposals, sources, roles, timeZones, importers } = usePage<HandbookPageProps>().props

  return (
    <AuthenticatedLayout title="Handbook">
      <Head title="Handbook" />
      <HandbookScreen pages={pages} suggestions={suggestions} directingRole={directingRole} proposals={proposals} sources={sources} roles={roles}
                     timeZones={timeZones} importers={importers} />
    </AuthenticatedLayout>
  )
}
