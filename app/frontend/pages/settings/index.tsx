import { Head } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"

export default function Settings() {
  return (
    <AuthenticatedLayout title="Settings">
      <Head title="Settings" />
    </AuthenticatedLayout>
  )
}
