import { router } from "@inertiajs/react"
import { IconSearch } from "@tabler/icons-react"
import { useState, type ChangeEvent, type FormEvent } from "react"

import { Input } from "@/components/ui/input"
import { operatorFindPath } from "@/lib/routes"

// Find box. Submits a pasted id or incident number to the find page, which opens a single match.
export function FindBox() {
  const [query, setQuery] = useState("")

  function change(event: ChangeEvent<HTMLInputElement>) {
    setQuery(event.target.value)
  }

  function find(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const pasted = query.trim()
    if (!pasted) {
      return
    }
    router.get(operatorFindPath({ q: pasted }))
  }

  return (
    <form role="search" onSubmit={find} className="border-b border-border px-3 py-3">
      <label className="relative block">
        <span className="sr-only">Find by id or incident number</span>
        <IconSearch className="text-muted-foreground pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2" />
        <Input
          id="operator-find"
          value={query}
          onChange={change}
          placeholder="Find an id or INC-042"
          autoComplete="off"
          spellCheck={false}
          className="h-8 pl-8 font-mono text-xs"
        />
      </label>
    </form>
  )
}
