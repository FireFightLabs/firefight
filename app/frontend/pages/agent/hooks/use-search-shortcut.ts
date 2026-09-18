import { useEffect } from "react"

// Command or control K opens chat search, the way it does in ChatGPT.
export function useSearchShortcut(openSearch: () => void) {
  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key !== "k" || !(event.metaKey || event.ctrlKey)) {
        return
      }

      event.preventDefault()
      openSearch()
    }

    window.addEventListener("keydown", onKey)

    return () => window.removeEventListener("keydown", onKey)
  }, [ openSearch ])
}
