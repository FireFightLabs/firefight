import { Head, usePage } from "@inertiajs/react"
import * as React from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { RolesTab } from "@/modules/settings/components/roles-tab"
import { StatusesTab } from "@/modules/settings/components/statuses-tab"
import { SeveritiesTab } from "@/modules/settings/components/severities-tab"
import { WebhooksTab } from "@/modules/settings/components/webhooks-tab"
import { ApiKeysTab } from "@/modules/settings/components/api-keys-tab"
import { CustomFieldsTab } from "@/modules/settings/components/custom-fields-tab"
import { FormsTab } from "@/modules/settings/components/forms-tab"
import type { ApiKey, IncidentRole, IncidentSeveritySettings, Webhook } from "@/types/serializers"
import type {
  CatalogTypeOption,
  IncidentFieldDefinitionSettings,
  IncidentFormSettings,
  LifecycleStageWithStatuses,
} from "@/modules/settings/types"
import type { SharedProps } from "@/types"

const validTabs = ["roles", "statuses", "severities", "custom-fields", "forms", "webhooks", "api-keys"] as const

function useUrlState() {
  const getParams = () => new URLSearchParams(window.location.search)

  const [tab, setTabState] = React.useState<string>(() => {
    const t = getParams().get("tab")
    return t && validTabs.includes(t as (typeof validTabs)[number]) ? t : "roles"
  })

  const [webhookId, setWebhookIdState] = React.useState<string | null>(() => {
    return getParams().get("webhook") || null
  })

  const [formId, setFormIdState] = React.useState<string | null>(() => {
    return getParams().get("form") || null
  })

  const updateUrl = (newTab: string, newWebhookId: string | null, newFormId: string | null) => {
    const params = new URLSearchParams()
    if (newTab !== "roles") params.set("tab", newTab)
    if (newWebhookId) params.set("webhook", newWebhookId)
    if (newFormId) params.set("form", newFormId)
    const qs = params.toString()
    const url = `${window.location.pathname}${qs ? `?${qs}` : ""}`
    window.history.replaceState(null, "", url)
  }

  const setTab = (t: string) => {
    setTabState(t)
    setWebhookIdState(null)
    setFormIdState(null)
    updateUrl(t, null, null)
  }

  const setWebhookId = (id: string | null) => {
    setWebhookIdState(id)
    updateUrl(tab, id, formId)
  }

  const setFormId = (id: string | null) => {
    setFormIdState(id)
    updateUrl(tab, webhookId, id)
  }

  return { tab, setTab, webhookId, setWebhookId, formId, setFormId }
}

interface SettingsPageProps extends SharedProps {
  [key: string]: unknown
  roles: IncidentRole[]
  lifecycleStages: LifecycleStageWithStatuses[]
  severities: IncidentSeveritySettings[]
  customFields: IncidentFieldDefinitionSettings[]
  forms: IncidentFormSettings[]
  catalogTypes: CatalogTypeOption[]
  webhooks: Webhook[]
  apiKeys: ApiKey[]
}

export default function Settings() {
  const { roles, lifecycleStages, severities, customFields, forms, catalogTypes, webhooks, apiKeys } = usePage<SettingsPageProps>().props
  const { tab, setTab, webhookId, setWebhookId, formId, setFormId } = useUrlState()

  return (
    <AuthenticatedLayout title="Settings">
      <Head title="Settings" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <Tabs value={tab} onValueChange={setTab} className="w-full">
          <TabsList className="flex h-auto flex-wrap gap-1 rounded-2xl border border-border/70 bg-muted/40 p-1.5">
            <TabsTrigger value="roles">Roles</TabsTrigger>
            <TabsTrigger value="statuses">Statuses</TabsTrigger>
            <TabsTrigger value="severities">Severities</TabsTrigger>
            <TabsTrigger value="custom-fields">Custom Fields</TabsTrigger>
            <TabsTrigger value="forms">Forms</TabsTrigger>
            <TabsTrigger value="webhooks">Webhooks</TabsTrigger>
            <TabsTrigger value="api-keys">API Keys</TabsTrigger>
          </TabsList>
          <div className="mt-6">
            <TabsContent value="roles"><RolesTab roles={roles} /></TabsContent>
            <TabsContent value="statuses"><StatusesTab lifecycleStages={lifecycleStages} /></TabsContent>
            <TabsContent value="severities"><SeveritiesTab severities={severities} /></TabsContent>
            <TabsContent value="custom-fields"><CustomFieldsTab fields={customFields} catalogTypes={catalogTypes} /></TabsContent>
            <TabsContent value="forms"><FormsTab forms={forms} customFields={customFields} selectedFormId={formId} onSelectForm={setFormId} onNavigateToCustomFields={() => setTab("custom-fields")} /></TabsContent>
            <TabsContent value="webhooks">
              <WebhooksTab webhooks={webhooks} activeWebhookId={webhookId} onWebhookSelect={setWebhookId} />
            </TabsContent>
            <TabsContent value="api-keys"><ApiKeysTab apiKeys={apiKeys} /></TabsContent>
          </div>
        </Tabs>
      </div>
    </AuthenticatedLayout>
  )
}
