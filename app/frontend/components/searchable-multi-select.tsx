import { IconCheck, IconChevronDown, IconX } from "@tabler/icons-react"
import { useState, type ReactNode } from "react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"

export interface SearchableMultiSelectOption {
  value: string
  label: string
  icon?: ReactNode
}

interface SearchableMultiSelectProps {
  value: string[]
  onValueChange: (value: string[]) => void
  options: SearchableMultiSelectOption[]
  placeholder?: string
  addMoreText?: string
  searchPlaceholder?: string
  emptyText?: string
  onOpen?: () => void
  renderBadge?: (option: SearchableMultiSelectOption) => ReactNode
  renderOption?: (option: SearchableMultiSelectOption) => ReactNode
}

export function SearchableMultiSelect({
  value,
  onValueChange,
  options,
  placeholder = "Select...",
  addMoreText = "Add more...",
  searchPlaceholder = "Search...",
  emptyText = "No results found",
  onOpen,
  renderBadge,
  renderOption,
}: SearchableMultiSelectProps) {
  const [open, setOpen] = useState(false)

  const toggle = (id: string) => {
    if (value.includes(id)) {
      onValueChange(value.filter((v) => v !== id))
    } else {
      onValueChange([ ...value, id ])
    }
  }

  const remove = (id: string) => {
    onValueChange(value.filter((v) => v !== id))
  }

  const defaultRender = (option: SearchableMultiSelectOption) => (
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

  return (
    <div className="flex flex-col gap-2">
      {value.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {value.map((id) => {
            const option = options.find((o) => o.value === id)
            return (
              <Badge key={id} variant="secondary" className="gap-1 pr-1">
                {renderBadge && option ? renderBadge(option) : (
                  <>
                    {option?.icon}
                    {option?.label ?? id}
                  </>
                )}
                <button
                  type="button"
                  onClick={() => remove(id)}
                  className="ml-0.5 rounded-sm hover:bg-muted-foreground/20 p-0.5"
                >
                  <IconX className="size-3" />
                </button>
              </Badge>
            )
          })}
        </div>
      )}
      <Popover open={open} onOpenChange={handleOpenChange}>
        <PopoverTrigger asChild>
          <Button variant="outline" role="combobox" aria-expanded={open} className="w-full justify-between font-normal">
            <span className="text-muted-foreground">
              {value.length === 0 ? placeholder : addMoreText}
            </span>
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
                    onSelect={() => toggle(option.value)}
                  >
                    {renderOption?.(option) ?? defaultRender(option)}
                    {value.includes(option.value) && <IconCheck className="ml-auto size-4" />}
                  </CommandItem>
                ))}
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
    </div>
  )
}
