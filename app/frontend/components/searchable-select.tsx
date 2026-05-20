import { IconCheck, IconChevronDown } from "@tabler/icons-react"
import { useState, type ReactNode } from "react"

import { Button } from "@/components/ui/button"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"

export interface SearchableSelectOption {
  value: string
  label: string
  icon?: ReactNode
}

interface SearchableSelectProps {
  value: string | null
  onValueChange: (value: string | null) => void
  options: SearchableSelectOption[]
  placeholder?: string
  searchPlaceholder?: string
  emptyText?: string
  onOpen?: () => void
  renderSelected?: (option: SearchableSelectOption) => ReactNode
  renderOption?: (option: SearchableSelectOption) => ReactNode
}

export function SearchableSelect({
  value,
  onValueChange,
  options,
  placeholder = "Select...",
  searchPlaceholder = "Search...",
  emptyText = "No results found",
  onOpen,
  renderSelected,
  renderOption,
}: SearchableSelectProps) {
  const [open, setOpen] = useState(false)
  const selected = options.find((o) => o.value === value)

  const defaultRender = (option: SearchableSelectOption) => (
    <div className="flex items-center gap-2">
      {option.icon}
      {option.label}
    </div>
  )

  return (
    <Popover open={open} onOpenChange={(o) => { setOpen(o); if (o) onOpen?.() }}>
      <PopoverTrigger asChild>
        <Button variant="outline" role="combobox" aria-expanded={open} className="w-full justify-between font-normal">
          {selected ? (
            renderSelected?.(selected) ?? defaultRender(selected)
          ) : (
            <span className="text-muted-foreground">{placeholder}</span>
          )}
          <IconChevronDown className="size-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[var(--radix-popover-trigger-width)] p-0" align="start">
        <Command>
          <CommandInput placeholder={searchPlaceholder} />
          <CommandList>
            <CommandEmpty>{emptyText}</CommandEmpty>
            <CommandGroup>
              {options.map((option) => (
                <CommandItem
                  key={option.value}
                  value={option.label}
                  onSelect={() => { onValueChange(option.value); setOpen(false) }}
                >
                  {renderOption?.(option) ?? defaultRender(option)}
                  {option.value === value && <IconCheck className="ml-auto size-4" />}
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}
