import { useEffect, useRef } from "react"
import { router, usePage } from "@inertiajs/react"
import type { Page } from "@inertiajs/core"

import { toast } from "sonner"

import type { FlashData } from "@/types"

function show(flash?: FlashData) {
  if (flash?.notice) toast.success(flash.notice)
  if (flash?.alert) toast.error(flash.alert)
}

// Bridges Rails flash into sonner so server-side guards (`redirect_to ... alert:`)
// are visible on Inertia pages. Keyed on the visit rather than the message text,
// because repeating an action repeats its wording: two drags both say "order
// updated", and deduping on content would swallow the second one.
export function FlashToaster() {
  const { flash } = usePage()
  const firstRender = useRef(true)

  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false
      show(flash)
    }

    return router.on("success", (event: CustomEvent<{ page: Page }>) => {
      show(event.detail.page.flash)
    })
    // Subscribed once: later flashes arrive through the visit event, not props.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return null
}
