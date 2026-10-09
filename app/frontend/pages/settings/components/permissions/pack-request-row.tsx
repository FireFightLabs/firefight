import { router } from "@inertiajs/react"
import { IconKey } from "@tabler/icons-react"

import type { PackRequest } from "@/types/serializers"
import { dismissPackRequestPath, givePackRequestPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import { formatDateTime } from "@/lib/formatters"
import { Blocked } from "@/components/blocked-tooltip"

export function PackRequestRow({ request, canManage }: { request: PackRequest; canManage: boolean }) {
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
