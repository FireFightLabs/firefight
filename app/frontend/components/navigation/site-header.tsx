import { IconSearch } from "@tabler/icons-react"
import type { ReactNode } from "react"

import { Button } from "@/components/ui/button"
import { SidebarTrigger } from "@/components/ui/sidebar"

// Apple keyboards say Cmd where everyone else says Ctrl.
const SHORTCUT = typeof navigator !== "undefined" && /Mac|iPhone|iPad/.test(navigator.userAgent) ? "⌘K" : "Ctrl K"

interface SiteHeaderProps {
  title: string
  actions?: ReactNode
  onSearch: () => void
  searchShortcut: boolean
}

export function SiteHeader({ title, actions, onSearch, searchShortcut }: SiteHeaderProps) {
  return (
    <header className="flex h-(--header-height) shrink-0 items-center gap-2 border-b transition-[width,height] ease-linear group-has-data-[collapsible=icon]/sidebar-wrapper:h-(--header-height)">
      <div className="flex w-full items-center gap-1 px-4 lg:gap-2 lg:px-6">
        <SidebarTrigger className="-ml-1" />
        <h1 className="truncate text-lg font-semibold tracking-tight text-fg-headline">{title}</h1>
        <div className="ml-auto flex items-center gap-2">
          <Button type="button" variant="outline" size="sm" onClick={onSearch} aria-label="Search the map, catalog and memory" className="gap-2 text-muted-foreground sm:w-56 sm:justify-start lg:w-64">
            <IconSearch className="size-4" />
            <span className="hidden sm:inline">Search</span>
            {searchShortcut && <kbd className="ml-auto hidden rounded border border-border px-1.5 font-sans text-[11px] text-muted-foreground md:inline">{SHORTCUT}</kbd>}
          </Button>
          {actions}
        </div>
      </div>
    </header>
  )
}
