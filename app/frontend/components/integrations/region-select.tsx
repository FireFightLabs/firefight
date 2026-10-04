import type { IntegrationProvider } from "@/types/serializers"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

type Region = IntegrationProvider["regions"][number]

// The first region is the one a connection that names none reaches, so the form starts on it.
export function defaultRegion(provider: IntegrationProvider) {
  return provider.regions[0]?.key ?? ""
}

// Where a provider runs its service, for a provider that offers more than one place, such as a US and an EU site.
export function RegionSelect({
  id,
  value,
  regions,
  onChange,
  compact = false,
}: {
  id?: string
  value: string
  regions: Region[]
  onChange: (value: string) => void
  compact?: boolean
}) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger id={id} className={compact ? "h-8 w-auto min-w-[9rem] shrink-0 text-sm" : undefined}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent align={compact ? "end" : "start"}>
        {regions.map((region) => (
          <SelectItem key={region.key} value={region.key}>
            {region.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}
