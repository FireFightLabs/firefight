import { IconChevronDown } from "@tabler/icons-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

export interface FilterOption {
  value: string
  label: string
}

interface FilterDropdownProps {
  label: string
  options: FilterOption[]
  selected: Set<string>
  onToggle: (value: string) => void
}

export function FilterDropdown({ label, options, selected, onToggle }: FilterDropdownProps) {
  const selectedLabel = selected.size === 1
    ? options.find((o) => selected.has(o.value))?.label
    : null

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="h-9 cursor-pointer focus-visible:ring-1 focus-visible:ring-border">
          <span className="text-muted-foreground">{label}</span>
          {selected.size > 0 && (
            <Badge variant="secondary" className="ml-0.5 rounded px-1 py-0 text-[11px] bg-primary/15 text-primary border-transparent">
              {selectedLabel ?? selected.size}
            </Badge>
          )}
          <IconChevronDown />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-40">
        {options.map((option) => (
          <DropdownMenuCheckboxItem
            key={option.value}
            checked={selected.has(option.value)}
            onCheckedChange={() => onToggle(option.value)}
            onSelect={(e) => e.preventDefault()}
          >
            {option.label}
          </DropdownMenuCheckboxItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
