import { router } from "@inertiajs/react"
import { useEffect, useRef, useState } from "react"

// Keeps unsaved words from being lost. Leaving the browser tab asks the browser's own question, and leaving for another
// page or opening another handbook page asks first with a dialog, which goes ahead only on Discard.
export function useUnsavedChanges(dirty: boolean) {
  const dirtyRef = useRef(dirty)
  const [ pending, setPending ] = useState<(() => void) | null>(null)

  useEffect(() => {
    dirtyRef.current = dirty
  }, [ dirty ])

  useEffect(() => {
    function warn(event: BeforeUnloadEvent) {
      if (dirtyRef.current) {
        event.preventDefault()
      }
    }
    window.addEventListener("beforeunload", warn)
    return () => window.removeEventListener("beforeunload", warn)
  }, [])

  // A save is a request of its own and goes ahead. Going to another page waits for the answer.
  useEffect(() => router.on("before", (event) => {
    const visit = event.detail.visit
    if (!dirtyRef.current || visit.method !== "get") {
      return true
    }
    setPending(() => () => router.visit(visit.url))
    return false
  }), [])

  function guard(action: () => void) {
    if (dirtyRef.current) {
      setPending(() => action)
    } else {
      action()
    }
  }

  function discard() {
    const action = pending
    dirtyRef.current = false
    setPending(null)
    action?.()
  }

  function keepEditing() {
    setPending(null)
  }

  return { guard, confirming: pending !== null, discard, keepEditing }
}
