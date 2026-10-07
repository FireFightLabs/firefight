import { router } from "@inertiajs/react"
import { IconKey } from "@tabler/icons-react"

import type { PackRequest } from "@/types/serializers"
import { dismissPackRequestPath, givePackRequestPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { formatDateTime } from "@/lib/formatters"
import { Blocked } from "@/pages/settings/components/blocked-tooltip"

// Packs members asked for after being refused a change, waiting on an admin. Give pack is the same grant as the screen
// makes, in every environment, and each answer confirms with a toast.
export function PackRequestsNotice({ requests, canManage }: { requests: PackRequest[]; canManage: boolean }) {
  if (requests.length === 0) {
    return null
  }

  return (
    <Card className="border-warning-border">
      <CardHeader>
        <CardTitle className="text-base">Waiting for a pack</CardTitle>
        <CardDescription>
          {requests.length === 1 ? "A member was" : `${requests.length} members were`} refused a change and asked for the pack
          that allows it.
        </CardDescription>
      </CardHeader>
      <CardContent className="p-0">
        <div className="divide-border divide-y border-t">
          {requests.map((request) => (
            <PackRequestRow key={request.id} request={request} canManage={canManage} />
          ))}
        </div>
      </CardContent>
    </Card>
  )
}

function PackRequestRow({ request, canManage }: { request: PackRequest; canManage: boolean }) {
  function give() {
    router.post(givePackRequestPath(request.id), {}, { preserveScroll: true })
  }

  function dismiss() {
    router.post(dismissPackRequestPath(request.id), {}, { preserveScroll: true })
  }

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 px-6 py-3">
      <div className="flex min-w-0 items-start gap-2">
        <IconKey className="text-muted-foreground mt-0.5 size-4 shrink-0" />
        <div className="min-w-0">
          <p className="text-sm">
            <span className="font-medium">{request.requesterName}</span> asks for <span className="font-medium">{request.packName}</span>
          </p>
          <p className="text-muted-foreground text-xs">
            {request.packDescription} Asked {formatDateTime(request.requestedAt)}.
          </p>
        </div>
      </div>
      {canManage && (
        <div className="flex shrink-0 items-center gap-2">
          <Button variant="ghost" size="sm" onClick={dismiss}>
            Dismiss
          </Button>
          <Blocked reason={request.giveBlockedReason ?? undefined}>
            <Button size="sm" disabled={Boolean(request.giveBlockedReason)} onClick={give}>
              Give pack
            </Button>
          </Blocked>
        </div>
      )}
    </div>
  )
}
