import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"

export const ALL = "all"

interface FilterSelectProps {
  label: string
  value: string | null
  onChange: (value: string) => void
  options: [string, string][]
}

export function FilterSelect({ label, value, onChange, options }: FilterSelectProps) {
  return (
    <Select value={value ?? ALL} onValueChange={onChange}>
      <SelectTrigger size="sm" className="h-8 min-w-32" aria-label={label}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={ALL}>{`${label}: all`}</SelectItem>
        {options.map(([ optionValue, optionLabel ]) => (
          <SelectItem key={optionValue} value={optionValue}>
            {optionLabel}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}
