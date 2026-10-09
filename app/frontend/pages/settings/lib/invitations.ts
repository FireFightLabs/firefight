import type { HttpResponse } from "@inertiajs/core"

import { retryWait } from "@/lib/http"

// The network throttle answers an invitation with a plain page, which a visit would otherwise open over Settings.
export function tooManyInvitationsMessage(response: HttpResponse): string {
  return `Too many invitations were sent from this network. Try again ${retryWait(response)}.`
}
