import { useEffect, useRef } from "react"
import { usePage } from "@inertiajs/react"

import { toast } from "sonner"

// Bridges Rails flash into sonner so server-side guards (`redirect_to ... alert:`)
// are visible on Inertia pages. Keyed on the page version so the same message
// re-fires after a later request rather than being swallowed as a duplicate.
export function FlashToaster() {
  const { flash, version } = usePage()
  const lastShown = useRef<string | null>(null)

  useEffect(() => {
    const key = `${version}:${flash.notice ?? ""}:${flash.alert ?? ""}`
    if (key === lastShown.current) return
    if (!flash.notice && !flash.alert) return

    lastShown.current = key
    if (flash.notice) toast.success(flash.notice)
    if (flash.alert) toast.error(flash.alert)
  }, [flash.notice, flash.alert, version])

  return null
}
