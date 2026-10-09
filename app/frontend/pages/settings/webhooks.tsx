import { useCallback, useState } from "react"
import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { useCan } from "@/lib/permissions"
import { WebhooksTab } from "@/pages/settings/components/webhooks/webhooks-tab"
import type { Webhook } from "@/types/serializers"
import type { SharedProps } from "@/types"
import { replaceQuery } from "@/lib/query"

interface WebhooksPageProps extends SharedProps {
  [key: string]: unknown
  webhooks: Webhook[]
}

export default function Webhooks() {
  const { webhooks } = usePage<WebhooksPageProps>().props
  const canManage = useCan("webhooks")

  const [activeWebhookId, setActiveWebhookId] = useState<string | null>(() => {
    const params = new URLSearchParams(window.location.search)
    return params.get("webhook") || null
  })

  const updateWebhookParam = useCallback((id: string | null) => {
    setActiveWebhookId(id)
    replaceQuery({ webhook: id })
  }, [])

  return (
    <AuthenticatedLayout title="Webhooks">
      <Head title="Webhooks" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <WebhooksTab
          webhooks={webhooks}
          canManage={canManage}
          activeWebhookId={activeWebhookId}
          onWebhookSelect={updateWebhookParam}
        />
      </div>
    </AuthenticatedLayout>
  )
}
