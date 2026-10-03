import { usePage } from "@inertiajs/react"

import { ProviderMark } from "@/components/integrations/provider-mark"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { whenClosed } from "@/lib/handlers"
import type { SharedProps } from "@/types"
import type { IntegrationProvider } from "@/types/serializers"

// What a provider is and what Halon can do through it, opened from the info button on its card.
export function ProviderAbout({ provider, onClose }: { provider: IntegrationProvider | null; onClose: () => void }) {
  const { agentAvailable } = usePage<SharedProps>().props

  return (
    <Dialog open={provider !== null} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="sm:max-w-lg">
        {provider && (
          <>
            <DialogHeader>
              <div className="flex items-center gap-3">
                <ProviderMark providerKey={provider.key} mark={provider.mark} color={provider.color} size={40} />
                <div className="flex flex-col gap-0.5 text-left">
                  <DialogTitle>{provider.name}</DialogTitle>
                  <span className="text-fg-secondary text-xs">{provider.category}</span>
                </div>
              </div>
              <DialogDescription className="pt-2 text-left">{provider.description}</DialogDescription>
            </DialogHeader>
            <dl className="flex flex-col gap-4 text-sm">
              {agentAvailable && (
                <div className="flex flex-col gap-1">
                  <dt className="text-fg-primary font-medium">With Halon</dt>
                  <dd className="text-fg-body">{provider.halon}</dd>
                </div>
              )}
              {provider.onMap && (
                <div className="flex flex-col gap-1">
                  <dt className="text-fg-primary font-medium">On the map</dt>
                  <dd className="text-fg-body">What {provider.name} holds is kept current on the map, with how it connects to everything else.</dd>
                </div>
              )}
              <div className="flex flex-col gap-1">
                <dt className="text-fg-primary font-medium">What it may change</dt>
                <dd className="text-fg-body">
                  Halon only uses the tools you switch on. A tool that changes something follows your permissions and approval
                  rules, and an investigation only reads.
                </dd>
              </div>
            </dl>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
