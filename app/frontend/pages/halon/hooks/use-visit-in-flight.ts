import { router } from "@inertiajs/react"
import { type RefObject, useEffect, useRef } from "react"

// Whether a visit the person started, such as leaving a run or opening a version, is still waiting on the server. A
// refresh sent meanwhile asks for the page being left, and its answer would put that page back over the new one.
export function useVisitInFlight(): RefObject<boolean> {
  const inFlight = useRef(false)

  useEffect(() => {
    const removeStart = router.on("start", (event) => {
      if (!event.detail.visit.async) {
        inFlight.current = true
      }
    })
    const removeFinish = router.on("finish", (event) => {
      if (!event.detail.visit.async) {
        inFlight.current = false
      }
    })
    return () => {
      removeStart()
      removeFinish()
    }
  }, [])

  return inFlight
}
