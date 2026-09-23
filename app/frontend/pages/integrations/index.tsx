import { useCallback, useState } from "react"
import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ConnectDialog } from "@/components/integrations/connect-dialog"
import { ConnectedCard } from "@/pages/integrations/components/connected-card"
import { ProviderGallery } from "@/pages/integrations/components/provider-gallery"
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import type { IntegrationProvider } from "@/types/serializers"
import type { EnvironmentOption, Integration } from "@/types/serializers"
import type { SharedProps } from "@/types"
import { whenClosed } from "@/lib/handlers"
import { useCan } from "@/lib/permissions"
import { INTEGRATION_CONNECT_QUERY_PARAM, INTEGRATION_DETAILS_QUERY_PARAM } from "@/lib/generated/constants"

// The details sheet lives in the address, so a link from a chat or a teammate opens the same connection.
function detailsFromUrl(): string | null {
  return new URLSearchParams(window.location.search).get(INTEGRATION_DETAILS_QUERY_PARAM)
}

// A link from Slack or a chat names the provider to connect, so its dialog is already open.
function connectFromUrl(providers: IntegrationProvider[]): IntegrationProvider | null {
  const requested = new URLSearchParams(window.location.search).get(INTEGRATION_CONNECT_QUERY_PARAM)
  return providers.find((provider) => provider.key === requested) ?? null
}

interface IntegrationsPageProps extends SharedProps {
  [key: string]: unknown
  integrations: Integration[]
  providers: IntegrationProvider[]
  categories: Record<string, string>
  environments: EnvironmentOption[]
}

export default function Integrations() {
  const { integrations, providers, categories, environments } = usePage<IntegrationsPageProps>().props
  const canManage = useCan("integrations")
  const [connecting, setConnecting] = useState<IntegrationProvider | null>(() => (canManage ? connectFromUrl(providers) : null))
  const [detailsId, setDetailsIdState] = useState<string | null>(detailsFromUrl)

  const setDetailsId = useCallback((id: string | null) => {
    setDetailsIdState(id)
    const params = new URLSearchParams(window.location.search)
    if (id) {
      params.set(INTEGRATION_DETAILS_QUERY_PARAM, id)
    } else {
      params.delete(INTEGRATION_DETAILS_QUERY_PARAM)
    }
    const query = params.toString()
    window.history.replaceState(null, "", `${window.location.pathname}${query ? `?${query}` : ""}`)
  }, [])

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

        <Sheet open={details !== null} onOpenChange={whenClosed(() => setDetailsId(null))}>
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
