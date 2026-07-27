import { useEffect, useRef } from "react"
import { router, usePage } from "@inertiajs/react"
import type { Page } from "@inertiajs/core"

import { toast } from "sonner"

import type { FlashData } from "@/types"

function show(flash?: FlashData) {
  if (flash?.notice) toast.success(flash.notice)
  if (flash?.alert) toast.error(flash.alert)
}

// Keyed on the visit rather than the message text: repeating an action repeats
// its wording, and deduping on content would swallow the second toast.
export function FlashToaster() {
  const { flash } = usePage()
  // The flash this mounted with. Later ones arrive on the visit event instead,
  // so the effect subscribes once and depends on nothing.
  const initialFlash = useRef(flash)
  const shownInitial = useRef(false)

  useEffect(() => {
    if (!shownInitial.current) {
      shownInitial.current = true
      show(initialFlash.current)
    }

    return router.on("success", (event: CustomEvent<{ page: Page }>) => {
      show(event.detail.page.flash)
    })
  }, [])

  return null
}
