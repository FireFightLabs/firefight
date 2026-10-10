import type { CSSProperties, ReactNode } from "react"
import { useSortable } from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import { IconFileText, IconGripVertical, IconRefresh, IconSearch, IconUserStar } from "@tabler/icons-react"

import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { HANDBOOK_HALON_READS, HANDBOOK_PAGE_KINDS } from "@/lib/generated/constants"
import { cn } from "@/lib/utils"
import type { HandbookPage } from "@/types/serializers"

interface SortablePageItemProps {
  page: HandbookPage
  selected: boolean
  sortable: boolean
  onSelect: (id: string) => void
}

const SEARCHED = "Long page. Halon searches it when needed instead of reading it whole."

// One page in the handbook's list, dragged by its handle to change the order Halon reads the pages in.
export function SortablePageItem({ page, selected, sortable, onSelect }: SortablePageItemProps) {
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, transform, transition, isDragging } = useSortable({ id: page.id, disabled: !sortable })
  const style: CSSProperties = { transform: CSS.Transform.toString(transform), transition }
  const synced = page.kind === HANDBOOK_PAGE_KINDS.SYNCED
  const Icon = synced ? IconRefresh : page.kind === HANDBOOK_PAGE_KINDS.DIRECTING ? IconUserStar : IconFileText
  const syncedFrom = page.sourceLabel ? `Synced from ${page.sourceLabel}. Change it at its source.` : "Synced from its source. Change it there."

  function select() {
    onSelect(page.id)
  }

  return (
    <li ref={setNodeRef} style={style} className={cn("group relative flex items-center rounded-md", isDragging && "z-10 bg-surface-popover shadow-popover")}>
      {sortable && (
        <button
          type="button"
          ref={setActivatorNodeRef}
          {...attributes}
          {...listeners}
          className="flex h-8 w-5 shrink-0 cursor-grab items-center justify-center text-fg-muted opacity-0 group-hover:opacity-100 focus-visible:opacity-100"
          aria-label={`Move ${page.title}`}
        >
          <IconGripVertical className="size-3.5" />
        </button>
      )}
      <button
        type="button"
        onClick={select}
        aria-current={selected ? "page" : undefined}
        className={cn(
          "flex min-w-0 flex-1 items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-fg-secondary hover:bg-hover hover:text-fg-primary",
          selected && "edge-bar bg-hover-2 text-fg-primary",
          !sortable && "ml-5",
        )}
      >
        {synced ? <IconHint label={syncedFrom}><Icon className="size-4 text-fg-muted" /></IconHint> : <Icon className="size-4 shrink-0 text-fg-muted" />}
        <span className="truncate">{page.title}</span>
        {page.halonReads === HANDBOOK_HALON_READS.SEARCHED && (
          <IconHint label={SEARCHED} className="ml-auto"><IconSearch className="size-3.5 text-fg-muted" /></IconHint>
        )}
      </button>
    </li>
  )
}

// An icon that says what it means on hover, and to a screen reader through its label.
function IconHint({ label, className, children }: { label: string; className?: string; children: ReactNode }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span className={cn("flex shrink-0", className)} role="img" aria-label={label}>{children}</span>
      </TooltipTrigger>
      <TooltipContent side="right" className="max-w-56">{label}</TooltipContent>
    </Tooltip>
  )
}
