import type { IntegrationProvider } from "@/types/serializers"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { SearchableMultiSelect } from "@/components/searchable-multi-select"
import { ScopeSelect, type ScopeListing } from "@/components/integrations/scope-select"

type ConnectField = IntegrationProvider["connectFields"][number]

// A field that holds several values keeps a list, every other field one string.
export type ConnectValue = string | string[]
export type ConnectValues = Record<string, ConnectValue>

// How a form lists what its credentials can read for a scope field, and when that listing is stale, such as a token
// typed again.
export interface ScopeLister {
  load: () => Promise<ScopeListing>
  key: string
}

function fieldLabel(field: ConnectField) {
  return field.optional ? `${field.label} (optional)` : field.label
}

function asList(value: ConnectValue | undefined) {
  if (Array.isArray(value)) {
    return value
  }
  return value ? [value] : []
}

function asText(value: ConnectValue | undefined) {
  return Array.isArray(value) ? value.join(",") : (value ?? "")
}

function FieldControl({
  field,
  value,
  compact,
  scopes,
  onChange,
}: {
  field: ConnectField
  value: ConnectValue | undefined
  compact: boolean
  scopes?: ScopeLister
  onChange: (key: string, value: ConnectValue) => void
}) {
  if (field.scope && scopes) {
    return (
      <ScopeSelect
        label={field.label}
        placeholder={field.placeholder}
        value={asList(value)}
        listingKey={scopes.key}
        load={scopes.load}
        onChange={(chosen) => onChange(field.key, chosen)}
      />
    )
  }
  if (field.multiple) {
    return (
      <SearchableMultiSelect
        value={asList(value)}
        options={field.options}
        onValueChange={(chosen) => onChange(field.key, chosen)}
        placeholder={field.placeholder || `Choose ${field.label.toLowerCase()}`}
        searchPlaceholder="Search..."
      />
    )
  }
  if (field.options.length > 0) {
    return (
      <Select value={asText(value)} onValueChange={(chosen) => onChange(field.key, chosen)}>
        <SelectTrigger id={`connect-${field.key}`} className={compact ? "h-8" : undefined}>
          <SelectValue placeholder={field.placeholder || `Choose ${field.label.toLowerCase()}`} />
        </SelectTrigger>
        <SelectContent>
          {field.options.map((option) => (
            <SelectItem key={option.value} value={option.value}>
              {option.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    )
  }
  return (
    <Input
      id={`connect-${field.key}`}
      inputMode={field.numeric ? "numeric" : undefined}
      autoComplete="off"
      spellCheck={false}
      value={asText(value)}
      onChange={(event) => onChange(field.key, event.target.value)}
      placeholder={field.placeholder}
      className={compact ? "h-8" : undefined}
    />
  )
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
