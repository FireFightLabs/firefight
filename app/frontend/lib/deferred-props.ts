import type { Page } from "@inertiajs/core"
import { router } from "@inertiajs/react"

// Props a deferred load was fetching when Inertia dropped it.
const dropped = new Set<string>()

function stillMissing(page: Page): string[] {
  const deferred = new Set(Object.values(page.initialDeferredProps ?? {}).flat())
  return [ ...dropped ].filter((prop) => deferred.has(prop) && page.props[prop] === undefined)
}

function reloadMissing(page: Page) {
  const missing = stillMissing(page)
  dropped.clear()
  if (missing.length === 0) {
    return
  }
  router.reload({ only: missing, preserveErrors: true, onCancel: () => missing.forEach((prop) => dropped.add(prop)) })
}

// Inertia drops a deferred load still in flight when a visit to another address starts, such as a change the page
// posts, and never asks again, so whatever it was fetching stays loading for good. This asks again for what the page
// still lacks once that visit lands. A visit that brings a page with deferred props of its own leaves them to Inertia.
export function reloadDroppedDeferredProps() {
  router.on("finish", (event) => {
    const visit = event.detail.visit
    const loadingDeferred = "deferredProps" in visit && visit.deferredProps === true
    if (loadingDeferred && (visit.cancelled || visit.interrupted)) {
      visit.only.forEach((prop) => dropped.add(prop))
    }
  })
  router.on("success", (event) => {
    const page = event.detail.page
    if (dropped.size === 0) {
      return
    }
    if (Object.keys(page.deferredProps ?? {}).length > 0) {
      dropped.clear()
      return
    }
    reloadMissing(page)
  })
}
