import { router } from "@inertiajs/react"

import { InvestigationStory, investigationTitle } from "@/components/investigations/investigation-story"
import { useLiveInvestigation } from "@/components/investigations/use-live-investigation"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { OPEN_INVESTIGATION_PROP } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { incidentPath } from "@/lib/routes"
import type { InvestigationDetail } from "@/types/serializers"

// A run read over its incident, opened from the timeline or a link in Slack. Closing it drops the run from the address.
export function InvestigationSheet({ incidentId, investigation }: { incidentId: string; investigation: InvestigationDetail | null }) {
  useLiveInvestigation(investigation?.status, OPEN_INVESTIGATION_PROP)

  function close() {
    router.get(incidentPath(incidentId), {}, { only: [OPEN_INVESTIGATION_PROP], preserveScroll: true, preserveState: true, replace: true })
  }

  return (
    <Sheet open={investigation != null} onOpenChange={whenClosed(close)}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-2xl">
        {investigation && (
          <div className="px-6 py-8">
            <SheetDescription className="sr-only">What Halon was asked, what it found and every step it took.</SheetDescription>
            <InvestigationStory
              investigation={investigation}
              title={<SheetTitle className="text-2xl font-semibold tracking-tight text-balance">{investigationTitle(investigation)}</SheetTitle>}
            />
          </div>
        )}
      </SheetContent>
    </Sheet>
  )
}
