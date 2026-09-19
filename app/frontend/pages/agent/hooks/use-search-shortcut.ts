import { useEffect } from "react"

// Command or control K opens chat search, the way it does in ChatGPT, except from inside a dialog
// that is already open.
export function useSearchShortcut(openSearch: () => void) {
  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key !== "k" || !(event.metaKey || event.ctrlKey)) {
        return
      }
      if (event.target instanceof Element && event.target.closest("[role=dialog]")) {
        return
      }

      event.preventDefault()
      openSearch()
    }

    window.addEventListener("keydown", onKey)

    return () => window.removeEventListener("keydown", onKey)
  }, [ openSearch ])
}
