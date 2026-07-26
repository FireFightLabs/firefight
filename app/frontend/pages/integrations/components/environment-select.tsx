import type { EnvironmentOption } from "@/pages/integrations/types"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

// "Unrestricted" is the absence of an environment id, but a Select needs a
// non-empty value to represent it. One sentinel, converted in one place, so
// no caller has to remember which empty-ish value the server expects.
export const ALL_ENVIRONMENTS = "all"

export function toEnvironmentId(value: string) {
  return value === ALL_ENVIRONMENTS ? "" : value
}

export function EnvironmentSelect({
  value,
  environments,
  onChange,
  compact = false,
}: {
  value: string | null
  environments: EnvironmentOption[]
  onChange: (value: string) => void
  compact?: boolean
}) {
  return (
    <Select value={value ?? ALL_ENVIRONMENTS} onValueChange={onChange}>
      <SelectTrigger className={compact ? "h-8 w-auto min-w-[9rem] shrink-0 text-sm" : undefined}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent align={compact ? "end" : "start"}>
        <SelectItem value={ALL_ENVIRONMENTS}>All environments</SelectItem>
        {environments.map((environment) => (
          <SelectItem key={environment.id} value={environment.id}>
            {environment.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}
