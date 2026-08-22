import type { Errors } from "@inertiajs/core"

/**
 * A field keyed error belongs under its field, where the reader is already
 * looking. The banner is for what the server could not attach to one, so
 * whatever a dialog renders inline gets filtered out of it.
 *
 *   <FormErrors errors={omitErrors(form.errors, "name")} />
 *   {form.errors.name && <p className="text-xs text-destructive">{form.errors.name}</p>}
 */
export function omitErrors(errors: Errors, ...fields: string[]): Errors {
  return Object.fromEntries(Object.entries(errors).filter(([field]) => !fields.includes(field)))
}

export function pickErrors(errors: Errors, ...fields: string[]): Errors {
  return Object.fromEntries(Object.entries(errors).filter(([field]) => fields.includes(field)))
}
