import { useEffect } from "react"

// Ignored inside an open dialog, so search never opens on top of another dialog.
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
