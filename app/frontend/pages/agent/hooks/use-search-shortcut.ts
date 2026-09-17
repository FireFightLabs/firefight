import { useEffect, type RefObject } from "react"

// Command or control K puts the cursor in the chat search, the way every list this size behaves.
export function useSearchShortcut(field: RefObject<HTMLInputElement | null>) {
  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key !== "k" || !(event.metaKey || event.ctrlKey)) {
        return
      }

      event.preventDefault()
      field.current?.focus()
    }

    window.addEventListener("keydown", onKey)

    return () => window.removeEventListener("keydown", onKey)
  }, [ field ])
}
