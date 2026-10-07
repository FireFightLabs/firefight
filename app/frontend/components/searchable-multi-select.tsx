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
  // Offers what was typed as a value of its own when no option has it, such as an id a list could not show.
  onAdd?: (typed: string) => void
  disabled?: boolean
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
  onAdd,
  disabled = false,
}: SearchableMultiSelectProps) {
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState("")
  const typed = search.trim()
  const offersTyped = Boolean(onAdd) && typed !== "" && !options.some((option) => option.value === typed) && !value.includes(typed)

  function addTyped() {
    onAdd?.(typed)
    setSearch("")
  }

  const toggle = (id: string) => {
    if (value.includes(id)) {
      onValueChange(value.filter((selected) => selected !== id))
    } else {
      onValueChange([ ...value, id ])
    }
  }

  const remove = (id: string) => {
    onValueChange(value.filter((selected) => selected !== id))
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
    } else {
      setSearch("")
    }
  }

  return (
    <div className="flex flex-col gap-2">
      {value.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {value.map((id) => {
            const option = options.find((candidate) => candidate.value === id)
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
                  disabled={disabled}
                  aria-label={`Remove ${option?.label ?? id}`}
                  className="ml-0.5 rounded-sm hover:bg-surface-selected p-0.5 disabled:pointer-events-none disabled:opacity-40"
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
          <Button variant="outline" role="combobox" aria-expanded={open} disabled={disabled} className="w-full justify-between font-normal">
            <span className="text-muted-foreground">
              {value.length === 0 ? placeholder : addMoreText}
            </span>
            <IconChevronDown className="size-4 shrink-0 text-fg-muted" />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-[var(--radix-popover-trigger-width)] p-0" align="start">
          <Command>
            <CommandInput placeholder={searchPlaceholder} value={search} onValueChange={setSearch} />
            <CommandList>
              <CommandEmpty>{emptyText}</CommandEmpty>
              <CommandGroup>
                {offersTyped && (
                  <CommandItem value={typed} onSelect={addTyped}>
                    Add &ldquo;{typed}&rdquo;
                  </CommandItem>
                )}
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
