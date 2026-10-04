import type { IntegrationProvider } from "@/types/serializers"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

type ConnectField = IntegrationProvider["connectFields"][number]

function fieldLabel(field: ConnectField) {
  return field.optional ? `${field.label} (optional)` : field.label
}

// What a provider's connect form asks beside the credentials, such as the organization its server's address names or
// the account an environment reads. The fields come from the registry. compact lays each out as a row of the one-click
// box, otherwise as a form field.
export function ConnectFields({
  fields,
  values,
  compact = false,
  onChange,
}: {
  fields: ConnectField[]
  values: Record<string, string>
  compact?: boolean
  onChange: (key: string, value: string) => void
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
        <Input
          id={`connect-${field.key}`}
          inputMode={field.numeric ? "numeric" : undefined}
          autoComplete="off"
          spellCheck={false}
          value={values[field.key] ?? ""}
          onChange={(event) => onChange(field.key, event.target.value)}
          placeholder={field.placeholder}
          className="h-8"
        />
      </div>
    ) : (
      <div key={field.key} className="flex flex-col gap-1.5">
        <Label htmlFor={`connect-${field.key}`}>{fieldLabel(field)}</Label>
        <Input
          id={`connect-${field.key}`}
          inputMode={field.numeric ? "numeric" : undefined}
          autoComplete="off"
          spellCheck={false}
          value={values[field.key] ?? ""}
          onChange={(event) => onChange(field.key, event.target.value)}
          placeholder={field.placeholder}
        />
        <p className="text-muted-foreground text-xs">{field.hint}</p>
      </div>
    ),
  )
}

// Whether every field the form asks that is not optional has a value. The server checks each value's shape.
export function connectFieldsComplete(fields: ConnectField[], values: Record<string, string>) {
  return fields.every((field) => field.optional || (values[field.key] ?? "").trim() !== "")
}
