import type { Page } from "@inertiajs/core"
import { router } from "@inertiajs/react"

// Props a deferred load was fetching when Inertia dropped it, kept until the page has them.
const dropped = new Set<string>()
let latest: Page | null = null
let recovering = false

function stillMissing(page: Page): string[] {
  const deferred = new Set(Object.values(page.initialDeferredProps ?? {}).flat())
  return [ ...dropped ].filter((prop) => deferred.has(prop) && page.props[prop] === undefined)
}

function recover(page: Page) {
  const missing = stillMissing(page)
  if (missing.length === 0) {
    dropped.clear()
    return
  }
  if (recovering) {
    return
  }
  recovering = true
  router.reload({ only: missing, preserveErrors: true, onFinish: () => { recovering = false } })
}

// Inertia drops a deferred load still in flight when a visit to another address starts, such as a change the page
// posts, and never asks again, so whatever it was fetching stays loading for good. This asks again for what the page
// still lacks once the next visit lands, whether it succeeded or came back with errors. A failed or cut short ask is
// tried again after the visit that follows. A page with deferred props of its own leaves them to Inertia.
export function reloadDroppedDeferredProps() {
  router.on("beforeUpdate", (event) => {
    latest = event.detail.page
  })
  router.on("finish", (event) => {
    const visit = event.detail.visit
    const loadingDeferred = "deferredProps" in visit && visit.deferredProps === true
    if (loadingDeferred && (visit.cancelled || visit.interrupted)) {
      visit.only.forEach((prop) => dropped.add(prop))
      return
    }
    if (dropped.size === 0 || !visit.completed || latest === null) {
      return
    }
    if (Object.keys(latest.deferredProps ?? {}).length > 0) {
      dropped.clear()
      return
    }
    recover(latest)
  })
}
