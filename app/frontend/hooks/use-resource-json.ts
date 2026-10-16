import { useEffect, useRef, useState } from "react"

import { requestJson } from "@/lib/http"

export type Loaded<T> = { state: "loading" } | { state: "failed" } | { state: "loaded"; answer: T }

// Reads one JSON answer when a panel opens, such as a resource's on the map, and again when its path changes. Raising
// readAgain reads the same path again in place. What is shown stays until the new answer replaces it, and stays if that
// read fails.
export function useResourceJson<T>(path: string, readAgain = 0): Loaded<T> {
  const [ loaded, setLoaded ] = useState<Loaded<T>>({ state: "loading" })
  const shownPath = useRef<string | null>(null)

  useEffect(() => {
    const controller = new AbortController()
    const inPlace = shownPath.current === path
    shownPath.current = path
    if (!inPlace) {
      setLoaded({ state: "loading" })
    }

    function readFailed() {
      setLoaded((shown) => (inPlace && shown.state === "loaded" ? shown : { state: "failed" }))
    }

    requestJson<T>(path, { method: "GET", signal: controller.signal })
      .then(({ ok, data }) => {
        if (ok && data) {
          setLoaded({ state: "loaded", answer: data })
        } else {
          readFailed()
        }
      })
      .catch(() => {
        if (!controller.signal.aborted) {
          readFailed()
        }
      })
    return () => {
      controller.abort()
    }
  }, [ path, readAgain ])

  return loaded
}
