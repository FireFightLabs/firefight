import { useCallback, useEffect, useRef, useState } from "react"

const SETTLE_MS = 200

// A failed request keeps the last results rather than showing no matches.
export function useRemoteSearch<T>(pathFor: (query: string) => string) {
  const [ results, setResults ] = useState<T[] | null>(null)
  const timer = useRef<number | undefined>(undefined)
  const inFlight = useRef<AbortController | undefined>(undefined)
  const pathForRef = useRef(pathFor)

  useEffect(() => {
    pathForRef.current = pathFor
  }, [ pathFor ])

  const cancel = useCallback(() => {
    window.clearTimeout(timer.current)
    inFlight.current?.abort()
  }, [])

  const search = useCallback((query: string) => {
    cancel()
    if (query.trim().length === 0) {
      setResults(null)
      return
    }

    timer.current = window.setTimeout(async () => {
      const controller = new AbortController()
      inFlight.current = controller
      try {
        const response = await fetch(pathForRef.current(query), {
          headers: { Accept: "application/json" },
          signal: controller.signal,
        })
        if (response.ok) {
          setResults((await response.json()) as T[])
        }
      } catch {
        // Aborted by a newer query or the network dropped, either way the last results stay.
      }
    }, SETTLE_MS)
  }, [ cancel ])

  useEffect(() => cancel, [ cancel ])

  return { results, search }
}
