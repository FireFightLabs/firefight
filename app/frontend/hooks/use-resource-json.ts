import { useEffect, useState } from "react"

import { requestJson } from "@/lib/http"

export type Loaded<T> = { state: "loading" } | { state: "failed" } | { state: "loaded"; answer: T }

// Reads one JSON answer when a panel opens, such as a resource's on the map, and again when its path changes.
export function useResourceJson<T>(path: string): Loaded<T> {
  const [ loaded, setLoaded ] = useState<Loaded<T>>({ state: "loading" })

  useEffect(() => {
    const controller = new AbortController()
    setLoaded({ state: "loading" })
    requestJson<T>(path, { method: "GET", signal: controller.signal })
      .then(({ ok, data }) => {
        setLoaded(ok && data ? { state: "loaded", answer: data } : { state: "failed" })
      })
      .catch(() => {
        if (!controller.signal.aborted) {
          setLoaded({ state: "failed" })
        }
      })
    return () => {
      controller.abort()
    }
  }, [ path ])

  return loaded
}
