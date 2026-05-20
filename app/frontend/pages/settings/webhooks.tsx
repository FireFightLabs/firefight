import { useCallback, useState } from "react"
import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { WebhooksTab } from "@/pages/settings/components/webhooks-tab"
import type { Webhook } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface WebhooksPageProps extends SharedProps {
  [key: string]: unknown
  webhooks: Webhook[]
}

export default function Webhooks() {
  const { webhooks } = usePage<WebhooksPageProps>().props

  const [activeWebhookId, setActiveWebhookId] = useState<string | null>(() => {
    const params = new URLSearchParams(window.location.search)
    return params.get("webhook") || null
  })

  const updateWebhookParam = useCallback((id: string | null) => {
    setActiveWebhookId(id)
    const params = new URLSearchParams(window.location.search)
    if (id) {
      params.set("webhook", id)
    } else {
      params.delete("webhook")
    }
    const qs = params.toString()
    const url = `${window.location.pathname}${qs ? `?${qs}` : ""}`
    window.history.replaceState(null, "", url)
  }, [])

  return (
    <AuthenticatedLayout title="Webhooks">
      <Head title="Webhooks" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <WebhooksTab
          webhooks={webhooks}
          activeWebhookId={activeWebhookId}
          onWebhookSelect={updateWebhookParam}
        />
      </div>
    </AuthenticatedLayout>
  )
}
