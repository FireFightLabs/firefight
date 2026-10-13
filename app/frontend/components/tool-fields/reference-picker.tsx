import { IconBraces } from "@tabler/icons-react"
import { useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"

interface ReferencePickerProps {
  // Each value a field can be filled from, written as it is read, such as {{steps.check.count}}, under its step.
  references: SearchableSelectOption[]
  label: string
  onPick: (reference: string) => void
}

function grouped(references: SearchableSelectOption[]): [string, SearchableSelectOption[]][] {
  const groups = new Map<string, SearchableSelectOption[]>()
  references.forEach((reference) => {
    const heading = reference.group ?? ""
    groups.set(heading, [ ...(groups.get(heading) ?? []), reference ])
  })
  return [ ...groups.entries() ]
}

// A button beside a field that lists what earlier steps hand on, and puts the one picked in the field, so nobody has to
// remember how a reference is written.
export function ReferencePicker({ references, label, onPick }: ReferencePickerProps) {
  const [ open, setOpen ] = useState(false)

  function pick(reference: string) {
    onPick(reference)
    setOpen(false)
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <Tooltip>
        <TooltipTrigger asChild>
          <PopoverTrigger asChild>
            <Button type="button" variant="outline" size="icon" className="size-9 shrink-0" aria-label={label}>
              <IconBraces className="size-4" />
            </Button>
          </PopoverTrigger>
        </TooltipTrigger>
        <TooltipContent>Use a value from an earlier step</TooltipContent>
      </Tooltip>
      <PopoverContent className="w-80 p-0" align="end">
        <Command>
          <CommandInput placeholder="Search earlier values" />
          <CommandList>
            <CommandEmpty>No earlier value by that name</CommandEmpty>
            {grouped(references).map(([ heading, options ]) => (
              <CommandGroup key={heading} heading={heading}>
                {options.map((option) => (
                  <CommandItem key={option.value} value={`${option.value} ${option.label} ${heading}`} onSelect={() => pick(option.value)} className="flex-col items-start gap-0.5">
                    <span className="font-mono text-xs text-fg-primary">{option.value}</span>
                    <span className="text-[11px] text-fg-muted">{option.label}</span>
                  </CommandItem>
                ))}
              </CommandGroup>
            ))}
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}
