import { useEffect } from "react"
import { usePage } from "@inertiajs/react"

import { toast } from "sonner"

import type { FlashData } from "@/types"

// Module scope because the layout remounts on every navigation, which would replay a shown flash.
// Keyed on the object Inertia hands over, a fresh one per response, so a repeated action still toasts.
let lastShown: FlashData | undefined

export function FlashToaster() {
  const { flash } = usePage()

  useEffect(() => {
    if (!flash || flash === lastShown) {
      return
    }

    lastShown = flash

    if (flash.notice) {
      toast.success(flash.notice)
    }

    if (flash.alert) {
      toast.error(flash.alert)
    }
  }, [flash])

  return null
}
