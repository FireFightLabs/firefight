import { IconExternalLink } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { liveUpdatesSetupIntegrationPath } from "@/lib/routes"
import { timeAgo } from "@/lib/time"
import type { Integration } from "@/types/serializers"

type Offer = NonNullable<NonNullable<Integration["environments"][number]["liveUpdates"]>["offer"]>
type OfferedPlace = Offer["places"][number]

function sendingLine(place: OfferedPlace): string {
  if (place.unavailable) {
    return place.unavailable
  }
  if (!place.sentAt) {
    return "Not sending yet"
  }
  return `Sending, last heard from ${timeAgo(place.sentAt)}`
}

// "Get changes instantly": what a person may set up at the provider so its changes arrive as they happen, one row per
// place it can be set up in. Each button opens the provider's own page in a new tab, through a redirect that fills in
// the connection's address and key, so the key is never in this page.
export function LiveUpdatesOffer({ integrationId, rowId, offer }: { integrationId: string; rowId: string; offer: Offer }) {
  function setupLink(place: OfferedPlace): string {
    return liveUpdatesSetupIntegrationPath(integrationId, { environment_row_id: rowId, place: place.place })
  }

  return (
    <div className="flex flex-col gap-2 pt-1">
      <p className="text-sm font-medium">Get changes instantly</p>
      <p className="text-muted-foreground text-xs">{offer.words}</p>
      {offer.unavailable ? (
        <p className="text-muted-foreground text-xs">{offer.unavailable}</p>
      ) : (
        <ul className="flex flex-col divide-y rounded-md border">
          {offer.places.map((place) => (
            <li key={place.place} className="flex items-center justify-between gap-3 px-3 py-2">
              <div className="min-w-0">
                <p className="truncate text-sm">{place.label}</p>
                <p className="text-muted-foreground text-xs">{sendingLine(place)}</p>
              </div>
              {!place.sentAt && !place.unavailable && (
                <Button asChild size="sm" variant="outline" className="h-8 shrink-0 gap-1.5">
                  <a href={setupLink(place)} target="_blank" rel="noreferrer">
                    {offer.action}
                    <IconExternalLink className="size-3.5" />
                  </a>
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}
      <p className="text-muted-foreground text-xs">{offer.removal}</p>
    </div>
  )
}
