import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { RolesTab } from "@/pages/settings/components/roles-tab"
import type { IncidentRole } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface RolesPageProps extends SharedProps {
  [key: string]: unknown
  roles: IncidentRole[]
}

export default function Roles() {
  const { roles } = usePage<RolesPageProps>().props

  return (
    <AuthenticatedLayout title="Roles">
      <Head title="Roles" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <RolesTab roles={roles} />
      </div>
    </AuthenticatedLayout>
  )
}
