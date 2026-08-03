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
  const selected = options.find((candidate) => candidate.value === value)

  const defaultRender = (option: SearchableSelectOption) => (
    <div className="flex items-center gap-2">
      {option.icon}
      {option.label}
    </div>
  )

  function handleOpenChange(next: boolean) {
    setOpen(next)
    if (next) {
      onOpen?.()
    }
  }

  function selectOption(optionValue: string) {
    onValueChange(optionValue)
    setOpen(false)
  }

  return (
    <Popover open={open} onOpenChange={handleOpenChange}>
      <PopoverTrigger asChild>
        <Button variant="outline" role="combobox" aria-expanded={open} className="w-full justify-between font-normal data-[state=open]:ring-1 data-[state=open]:ring-ring/20">
          {selected ? (
            renderSelected?.(selected) ?? defaultRender(selected)
          ) : (
            <span className="text-muted-foreground">{placeholder}</span>
          )}
          <IconChevronDown className="size-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[var(--radix-popover-trigger-width)] p-0" align="start" onOpenAutoFocus={(event) => event.preventDefault()}>
        <Command className="py-3 outline-none">
          <div className="mx-2 my-1 rounded-md border border-input focus-within:border-ring focus-within:ring-1 focus-within:ring-ring/20 transition-[color,box-shadow] [&_[data-slot=command-input-wrapper]]:border-0">
            <CommandInput placeholder={searchPlaceholder} className="!border-0 !outline-none !shadow-none !ring-0 focus:!border-0 focus:!outline-none focus:!shadow-none focus:!ring-0" />
          </div>
          <CommandList>
            <CommandEmpty>{emptyText}</CommandEmpty>
            <CommandGroup>
              {options.map((option) => (
                <CommandItem
                  key={option.value}
                  value={option.label}
                  onSelect={() => selectOption(option.value)}
                  className="cursor-pointer"
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
