import { useState } from "react"
import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ConnectDialog } from "@/pages/integrations/components/connect-dialog"
import { ConnectedCard } from "@/pages/integrations/components/connected-card"
import { ProviderGallery } from "@/pages/integrations/components/provider-gallery"
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import type { ProviderEntry } from "@/pages/integrations/types"
import type { EnvironmentOption, Integration } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface IntegrationsPageProps extends SharedProps {
  [key: string]: unknown
  integrations: Integration[]
  providers: ProviderEntry[]
  categories: Record<string, string>
  environments: EnvironmentOption[]
  canManage: boolean
}

export default function Integrations() {
  const { integrations, providers, categories, environments, canManage } = usePage<IntegrationsPageProps>().props
  const [connecting, setConnecting] = useState<ProviderEntry | null>(null)
  const [detailsId, setDetailsId] = useState<string | null>(null)

  const details = integrations.find((integration) => integration.id === detailsId) ?? null

  return (
    <AuthenticatedLayout title="Integrations">
      <Head title="Integrations" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <ProviderGallery
          providers={providers}
          categories={categories}
          integrations={integrations}
          canManage={canManage}
          onConnect={setConnecting}
          onDetails={(integration) => setDetailsId(integration.id)}
        />

        <ConnectDialog
          provider={connecting}
          environments={environments}
          existingNames={integrations
            .filter((integration) => integration.provider === connecting?.key)
            .map((integration) => integration.name)}
          onDismiss={() => setConnecting(null)}
        />

        <Sheet open={details !== null} onOpenChange={(open) => { if (!open) { setDetailsId(null) } }}>
          <SheetContent className="overflow-y-auto sm:max-w-lg">
            <SheetHeader>
              <SheetTitle>Connection details</SheetTitle>
            </SheetHeader>
            {details && (
              <div className="px-4 pb-6">
                <ConnectedCard
                  integration={details}
                  provider={providers.find((provider) => provider.key === details.provider)}
                  environments={environments}
                  canManage={canManage}
                  onAddConnection={() => {
                    const provider = providers.find((entry) => entry.key === details.provider) ?? null
                    setDetailsId(null)
                    setConnecting(provider)
                  }}
                />
              </div>
            )}
          </SheetContent>
        </Sheet>
      </div>
    </AuthenticatedLayout>
  )
}
