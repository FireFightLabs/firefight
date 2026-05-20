import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ApiKeysTab } from "@/pages/settings/components/api-keys-tab"
import type { ApiKey } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface ApiKeysPageProps extends SharedProps {
  [key: string]: unknown
  apiKeys: ApiKey[]
}

export default function ApiKeys() {
  const { apiKeys } = usePage<ApiKeysPageProps>().props

  return (
    <AuthenticatedLayout title="API Keys">
      <Head title="API Keys" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <ApiKeysTab apiKeys={apiKeys} />
      </div>
    </AuthenticatedLayout>
  )
}
