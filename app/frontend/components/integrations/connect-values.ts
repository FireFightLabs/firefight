import type { ScopeListing } from "@/components/integrations/scope-select"

// A field that holds several values keeps a list, every other field one string.
export type ConnectValue = string | string[]
export type ConnectValues = Record<string, ConnectValue>

// How a form lists what its credentials can read for a scope field, and when that listing is stale, such as a token
// typed again.
export interface ScopeLister {
  load: () => Promise<ScopeListing>
  key: string
}

export function asList(value: ConnectValue | undefined) {
  if (Array.isArray(value)) {
    return value
  }
  return value ? [value] : []
}

export function asText(value: ConnectValue | undefined) {
  return Array.isArray(value) ? value.join(",") : (value ?? "")
}
