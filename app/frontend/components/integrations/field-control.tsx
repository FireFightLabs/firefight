import type { IntegrationProvider } from "@/types/serializers"
import { Input } from "@/components/ui/input"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { SearchableMultiSelect } from "@/components/searchable-multi-select"
import { ScopeSelect } from "@/components/integrations/scope-select"
import { asList, asText, type ConnectValue, type ScopeLister } from "@/components/integrations/connect-values"

type ConnectField = IntegrationProvider["connectFields"][number]

// The control for one connect field, by what it holds: what the credentials can read, several choices, one choice, or text.
export function FieldControl({
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
