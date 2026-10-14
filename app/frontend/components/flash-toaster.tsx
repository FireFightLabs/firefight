import { useEffect } from "react"
import { router, usePage } from "@inertiajs/react"

import { toast } from "sonner"

import type { FlashData, FlashLink } from "@/types"

// Module scope because the layout remounts on every navigation, which would replay a shown flash.
// Keyed on the object Inertia hands over, a fresh one per response, so a repeated action still toasts.
let lastShown: FlashData | undefined
let openingPageShown = false

function openLink(link: FlashLink) {
  window.open(link.url, "_blank", "noopener,noreferrer")
}

function actionFor(link: FlashLink | undefined) {
  if (!link) {
    return undefined
  }
  return { label: link.label, onClick: () => openLink(link) }
}

function show(flash: FlashData) {
  if (flash === lastShown) {
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
}

// Inertia announces each answer's flash once. It also copies the flash onto the page again, as a fresh object, when the
// page's deferred props arrive, so a flash read from the page itself was shown twice. Only the page the app opened on
// is read from the page, once the toaster is there to draw it, and every later one from the announcement.
function announced(flash: FlashData) {
  if (openingPageShown) {
    show(flash)
  }
}

router.on("flash", (event) => announced(event.detail.flash))

export function FlashToaster() {
  const { flash } = usePage()

  useEffect(() => {
    if (openingPageShown) {
      return
    }
    openingPageShown = true
    show(flash)
  }, [flash])

  return null
}
