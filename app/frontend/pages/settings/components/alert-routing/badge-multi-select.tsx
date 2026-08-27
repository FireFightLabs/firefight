import { IconX } from "@tabler/icons-react"

import { cn } from "@/lib/utils"
import { Badge } from "@/components/ui/badge"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

export function BadgeMultiSelect({
  selected,
  options,
  placeholder,
  onAdd,
  onRemove,
  className,
  stacked = false,
}: {
  selected: string[]
  options: { value: string; label: string }[]
  placeholder: string
  onAdd: (value: string) => void
  onRemove: (value: string) => void
  className?: string
  stacked?: boolean
}) {
  const available = options.filter((option) => !selected.includes(option.value))
  const labelFor = (value: string) => options.find((option) => option.value === value)?.label ?? value

  if (stacked) {
    return (
      <div className={cn("flex flex-col gap-2", className)}>
        <Select value="" onValueChange={onAdd} disabled={available.length === 0}>
          <SelectTrigger className="w-full">
            <SelectValue placeholder={placeholder} />
          </SelectTrigger>
          <SelectContent>
            {available.map((option) => (
              <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        {selected.length > 0 && (
          <div className="flex flex-wrap items-center gap-1.5">
            {selected.map((value) => (
              <Badge key={value} variant="secondary" className="gap-1">
                {labelFor(value)}
                <button type="button" aria-label={`Remove ${labelFor(value)}`} onClick={() => onRemove(value)} className="ml-0.5">
                  <IconX className="size-3" />
                </button>
              </Badge>
            ))}
          </div>
        )}
      </div>
    )
  }

  return (
    <div className={cn("flex flex-wrap items-center gap-1.5", className)}>
      {selected.map((value) => (
        <Badge key={value} variant="secondary" className="gap-1">
          {labelFor(value)}
          <button
            type="button"
            aria-label={`Remove ${labelFor(value)}`}
            onClick={() => onRemove(value)}
            className="ml-0.5"
          >
            <IconX className="size-3" />
          </button>
        </Badge>
      ))}
      {available.length > 0 && (
        <Select value="" onValueChange={onAdd}>
          <SelectTrigger className="h-7 w-40 text-xs">
            <SelectValue placeholder={placeholder} />
          </SelectTrigger>
          <SelectContent>
            {available.map((option) => (
              <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      )}
    </div>
  )
}
