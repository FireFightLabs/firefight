import type { Errors } from "@inertiajs/core"

// Field errors render under their field, so the banner only shows what the
// server could not attach to one.
export function omitErrors(errors: Errors, ...fields: string[]): Errors {
  return Object.fromEntries(Object.entries(errors).filter(([field]) => !fields.includes(field)))
}

export function pickErrors(errors: Errors, ...fields: string[]): Errors {
  return Object.fromEntries(Object.entries(errors).filter(([field]) => fields.includes(field)))
}
