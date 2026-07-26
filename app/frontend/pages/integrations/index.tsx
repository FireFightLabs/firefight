import { useState } from "react"
import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ConnectDialog } from "@/pages/integrations/components/connect-dialog"
import { ConnectedCard } from "@/pages/integrations/components/connected-card"
import { ProviderGallery } from "@/pages/integrations/components/provider-gallery"
import type { EnvironmentOption, ProviderEntry } from "@/pages/integrations/types"
import type { Integration } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface IntegrationsPageProps extends SharedProps {
  [key: string]: unknown
  integrations: Integration[]
  providers: ProviderEntry[]
  environments: EnvironmentOption[]
  canManage: boolean
}

export default function Integrations() {
  const { integrations, providers, environments, canManage } = usePage<IntegrationsPageProps>().props
  const [connecting, setConnecting] = useState<ProviderEntry | null>(null)

  return (
    <AuthenticatedLayout title="Integrations">
      <Head title="Integrations" />
      <div className="flex flex-col gap-8 px-4 py-4 md:py-6 lg:px-6">
        {integrations.length > 0 && (
          <section className="flex flex-col gap-3">
            <h2 className="text-lg font-semibold">Connected</h2>
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
              {integrations.map((integration) => (
                <ConnectedCard
                  key={integration.id}
                  integration={integration}
                  provider={providers.find((provider) => provider.key === integration.provider)}
                  canManage={canManage}
                />
              ))}
            </div>
          </section>
        )}

        <ProviderGallery providers={providers} canManage={canManage} onConnect={setConnecting} />

        <ConnectDialog provider={connecting} environments={environments} onDismiss={() => setConnecting(null)} />
      </div>
    </AuthenticatedLayout>
  )
}
