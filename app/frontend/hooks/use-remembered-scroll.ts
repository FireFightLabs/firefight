import { useLayoutEffect, useRef } from "react"

// Kept for the life of the tab. A visit swaps the page but keeps this module, so a remount reads it back.
const positions = new Map<string, number>()

// Every page renders its own layout, so a visit rebuilds the element and it would start at the top again.
// The position is put back before paint, so the move never shows.
export function useRememberedScroll<Element extends HTMLElement>(key: string) {
  const ref = useRef<Element>(null)

  useLayoutEffect(() => {
    const element = ref.current
    if (!element) {
      return
    }
    element.scrollTop = positions.get(key) ?? 0

    function remember() {
      if (element) {
        positions.set(key, element.scrollTop)
      }
    }
    element.addEventListener("scroll", remember, { passive: true })
    return () => element.removeEventListener("scroll", remember)
  }, [ key ])

  return ref
}
