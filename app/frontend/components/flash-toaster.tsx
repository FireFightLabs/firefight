import { useEffect } from "react"
import { usePage } from "@inertiajs/react"

import { toast } from "sonner"

import type { FlashData } from "@/types"

// Module scope on purpose. This renders inside AuthenticatedLayout, and every
// page imports that layout for itself rather than Inertia keeping one alive
// across visits, so the component remounts on each navigation. Anything held in
// component state resets with it and replays a flash already on screen.
//
// Keyed on the object Inertia hands over, which is a fresh one per response, so
// repeating an action still toasts again even when the wording is identical.
let lastShown: FlashData | undefined

export function FlashToaster() {
  const { flash } = usePage()

  useEffect(() => {
    if (!flash || flash === lastShown) return

    lastShown = flash
    if (flash.notice) toast.success(flash.notice)
    if (flash.alert) toast.error(flash.alert)
  }, [flash])

  return null
}
