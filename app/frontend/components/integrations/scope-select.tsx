import { useState } from "react"

import { CONNECT_SCOPE_ALL } from "@/lib/generated/constants"
import { SearchableMultiSelect, type SearchableMultiSelectOption } from "@/components/searchable-multi-select"

export interface ScopeListing {
  options: SearchableMultiSelectOption[]
  error: string | null
}

const ALL_OPTION: SearchableMultiSelectOption = { value: CONNECT_SCOPE_ALL.VALUE, label: CONNECT_SCOPE_ALL.LABEL }

// Every scope the credentials can read stands alone, so choosing it clears the others and choosing another clears it.
function exclusive(previous: string[], chosen: string[]) {
  const all = CONNECT_SCOPE_ALL.VALUE
  if (chosen.includes(all) && !previous.includes(all)) {
    return [all]
  }
  return chosen.length > 1 ? chosen.filter((value) => value !== all) : chosen
}

// What a connection reads at its provider, such as Northflank projects: one, several, or all the credentials can read.
// The choices are listed from the provider when the list first opens, by load, and listed again when listingKey
// changes, such as a token typed again. An id the listing could not show can still be typed.
export function ScopeSelect({
  label,
  placeholder,
  value,
  known = [],
  listingKey,
  load,
  onChange,
  disabled = false,
}: {
  label: string
  placeholder: string
  value: string[]
  known?: SearchableMultiSelectOption[]
  listingKey: string
  load: () => Promise<ScopeListing>
  onChange: (value: string[]) => void
  disabled?: boolean
}) {
  const [listing, setListing] = useState<{ key: string; options: SearchableMultiSelectOption[]; error: string | null } | null>(null)
  const [loading, setLoading] = useState(false)
  const current = listing?.key === listingKey ? listing : null
  const listed = current?.options ?? []
  const options = [ALL_OPTION, ...listed, ...known.filter((option) => !listed.some((each) => each.value === option.value))]

  async function list() {
    if (current || loading) {
      return
    }
    setLoading(true)
    try {
      const found = await load()
      setListing({ key: listingKey, options: found.options, error: found.error })
    } catch {
      setListing({ key: listingKey, options: [], error: "Firefight could not reach the provider to list them." })
    } finally {
      setLoading(false)
    }
  }

  function choose(chosen: string[]) {
    onChange(exclusive(value, chosen))
  }

  function add(typed: string) {
    onChange(exclusive(value, [...value, typed]))
  }

  return (
    <div className="flex flex-col gap-1.5">
      <SearchableMultiSelect
        value={value}
        options={options}
        onValueChange={choose}
        onOpen={list}
        onAdd={add}
        disabled={disabled}
        placeholder={placeholder || `Choose ${label.toLowerCase()}`}
        searchPlaceholder={`Search ${label.toLowerCase()}, or type an id`}
        emptyText={loading ? `Listing ${label.toLowerCase()}...` : `No ${label.toLowerCase()} found`}
      />
      {current?.error && <p className="text-destructive text-xs">{current.error} Type an id to add one.</p>}
    </div>
  )
}
