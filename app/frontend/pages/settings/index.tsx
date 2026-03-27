import { Head, usePage } from "@inertiajs/react"
import * as React from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { RolesTab } from "@/modules/settings/components/roles-tab"
import { StatusesTab } from "@/modules/settings/components/statuses-tab"
import { SeveritiesTab } from "@/modules/settings/components/severities-tab"
import { WebhooksTab } from "@/modules/settings/components/webhooks-tab"
import { ApiKeysTab } from "@/modules/settings/components/api-keys-tab"
import type { IncidentRole } from "@/types/serializers"
import type { LifecycleStageWithStatuses } from "@/modules/settings/types"

const validTabs = ["roles", "statuses", "severities", "webhooks", "api-keys"] as const

function useUrlState() {
  const getParams = () => new URLSearchParams(window.location.search)

  const [tab, setTabState] = React.useState<string>(() => {
    const t = getParams().get("tab")
    return t && validTabs.includes(t as (typeof validTabs)[number]) ? t : "roles"
  })

  const [webhookId, setWebhookIdState] = React.useState<string | null>(() => {
    return getParams().get("webhook") || null
  })

  const updateUrl = (newTab: string, newWebhookId: string | null) => {
    const params = new URLSearchParams()
    if (newTab !== "roles") params.set("tab", newTab)
    if (newWebhookId) params.set("webhook", newWebhookId)
    const qs = params.toString()
    const url = `${window.location.pathname}${qs ? `?${qs}` : ""}`
    window.history.replaceState(null, "", url)
  }

  const setTab = (t: string) => {
    setTabState(t)
    setWebhookIdState(null)
    updateUrl(t, null)
  }

  const setWebhookId = (id: string | null) => {
    setWebhookIdState(id)
    updateUrl(tab, id)
  }

  return { tab, setTab, webhookId, setWebhookId }
}

interface SettingsPageProps {
  roles: IncidentRole[]
  lifecycleStages: LifecycleStageWithStatuses[]
}

export default function Settings() {
  const { roles, lifecycleStages } = usePage<SettingsPageProps>().props
  const { tab, setTab, webhookId, setWebhookId } = useUrlState()

  return (
    <AuthenticatedLayout title="Settings">
      <Head title="Settings" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <Tabs value={tab} onValueChange={setTab} className="w-full">
          <TabsList>
            <TabsTrigger value="roles">Roles</TabsTrigger>
            <TabsTrigger value="statuses">Statuses</TabsTrigger>
            <TabsTrigger value="severities">Severities</TabsTrigger>
            <TabsTrigger value="webhooks">Webhooks</TabsTrigger>
            <TabsTrigger value="api-keys">API Keys</TabsTrigger>
          </TabsList>
          <div className="mt-6">
            <TabsContent value="roles"><RolesTab roles={roles} /></TabsContent>
            <TabsContent value="statuses"><StatusesTab lifecycleStages={lifecycleStages} /></TabsContent>
            <TabsContent value="severities"><SeveritiesTab /></TabsContent>
            <TabsContent value="webhooks">
              <WebhooksTab activeWebhookId={webhookId} onWebhookSelect={setWebhookId} />
            </TabsContent>
            <TabsContent value="api-keys"><ApiKeysTab /></TabsContent>
          </div>
        </Tabs>
      </div>
    </AuthenticatedLayout>
  )
}
