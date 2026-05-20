import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { TypesTab } from "@/pages/settings/components/types-tab"
import type { IncidentTypeSettings } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface TypesPageProps extends SharedProps {
  [key: string]: unknown
  types: IncidentTypeSettings[]
}

export default function Types() {
  const { types } = usePage<TypesPageProps>().props

  return (
    <AuthenticatedLayout title="Types">
      <Head title="Types" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <TypesTab types={types} />
      </div>
    </AuthenticatedLayout>
  )
}
