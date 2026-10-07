import { useEffect } from "react"
import { usePage } from "@inertiajs/react"

import { toast } from "sonner"

import type { FlashData, FlashLink } from "@/types"

// Module scope because the layout remounts on every navigation, which would replay a shown flash.
// Keyed on the object Inertia hands over, a fresh one per response, so a repeated action still toasts.
let lastShown: FlashData | undefined

function openLink(link: FlashLink) {
  window.open(link.url, "_blank", "noopener,noreferrer")
}

function actionFor(link: FlashLink | undefined) {
  if (!link) {
    return undefined
  }
  return { label: link.label, onClick: () => openLink(link) }
}

export function FlashToaster() {
  const { flash } = usePage()

  useEffect(() => {
    if (!flash || flash === lastShown) {
      return
    }

    lastShown = flash

    // The first link rides on the toast it belongs to, and any further one gets a toast of its own.
    const [firstLink, ...otherLinks] = flash.links ?? []

    if (flash.notice) {
      toast.success(flash.notice, { action: actionFor(firstLink) })
    }

    if (flash.alert) {
      toast.error(flash.alert, { action: flash.notice ? undefined : actionFor(firstLink) })
    }

    otherLinks.forEach((link) => {
      toast(link.label, { action: actionFor(link) })
    })
  }, [flash])

  return null
}
