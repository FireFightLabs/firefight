import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconChevronDown } from "@tabler/icons-react"

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

export type InlineChoice = { value: string; label: string }

// A badge or cell that changes what it shows. One field, one request, no
// dialog. Anything that needs the workspace's configured questions asked goes
// through the lifecycle form instead, which is why this only ever sends a
// single key.
export function InlineSelect({
  trigger,
  choices,
  selected,
  path,
  payload,
  disabled,
  align = "start",
}: {
  trigger: React.ReactNode
  choices: InlineChoice[]
  selected?: string | null
  path: string
  payload: (value: string) => Record<string, string>
  disabled?: boolean
  align?: "start" | "end"
}) {
  const [saving, setSaving] = useState(false)

  function pick(value: string) {
    if (value === selected) {
      return
    }

    setSaving(true)
    router.patch(path, payload(value), {
      preserveScroll: true,
      onFinish: () => setSaving(false),
    })
  }

  if (disabled) {
    return <>{trigger}</>
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        disabled={saving}
        className="group inline-flex items-center gap-1 rounded-full outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-60"
      >
        {trigger}
        <IconChevronDown className="size-3 shrink-0 text-muted-foreground/50 transition-colors group-hover:text-muted-foreground" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align={align} className="max-h-72 overflow-y-auto">
        {choices.map((choice) => (
          <DropdownMenuItem
            key={choice.value}
            onSelect={() => pick(choice.value)}
            className={choice.value === selected ? "font-medium text-foreground" : ""}
          >
            {choice.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
