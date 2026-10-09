import type { IntegrationProvider } from "@/types/serializers"
import { Label } from "@/components/ui/label"
import { FieldControl } from "@/components/integrations/field-control"
import { asList, type ConnectValue, type ConnectValues, type ScopeLister } from "@/components/integrations/connect-values"

export type { ConnectValue, ConnectValues, ScopeLister } from "@/components/integrations/connect-values"

type ConnectField = IntegrationProvider["connectFields"][number]

function fieldLabel(field: ConnectField) {
  return field.optional ? `${field.label} (optional)` : field.label
}

// What a provider's connect form asks beside the credentials, such as the organization its server's address names, the
// account an environment reads or the regions an account runs in. The fields come from the registry. compact lays each
// out as a row of the one-click box, otherwise as a form field. scopes lists what the credentials can read, for a field
// that names it, such as projects.
export function ConnectFields({
  fields,
  values,
  compact = false,
  scopes,
  onChange,
}: {
  fields: ConnectField[]
  values: ConnectValues
  compact?: boolean
  scopes?: ScopeLister
  onChange: (key: string, value: ConnectValue) => void
}) {
  return fields.map((field) =>
    compact ? (
      <div key={field.key} className="flex flex-col gap-1.5 px-3 py-2.5">
        <div className="min-w-0">
          <Label htmlFor={`connect-${field.key}`} className="text-sm font-medium">
            {fieldLabel(field)}
          </Label>
          <p className="text-muted-foreground text-xs">{field.hint}</p>
        </div>
        <FieldControl field={field} value={values[field.key]} compact scopes={scopes} onChange={onChange} />
      </div>
    ) : (
      <div key={field.key} className="flex flex-col gap-1.5">
        <Label htmlFor={`connect-${field.key}`}>{fieldLabel(field)}</Label>
        <FieldControl field={field} value={values[field.key]} compact={false} scopes={scopes} onChange={onChange} />
        <p className="text-muted-foreground text-xs">{field.hint}</p>
      </div>
    ),
  )
}

// Whether every field the form asks that is not optional has a value. The server checks each value's shape.
export function connectFieldsComplete(fields: ConnectField[], values: ConnectValues) {
  return fields.every((field) => field.optional || asList(values[field.key]).some((value) => value.trim() !== ""))
}

// The values as a full-page address carries them, a list as one entry per value.
export function appendConnectValues(params: URLSearchParams, values: ConnectValues) {
  Object.entries(values).forEach(([key, value]) => {
    if (Array.isArray(value)) {
      value.forEach((each) => params.append(`fields[${key}][]`, each))
    } else {
      params.set(`fields[${key}]`, value.trim())
    }
  })
}
