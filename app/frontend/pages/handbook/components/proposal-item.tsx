import { IconSparkles } from "@tabler/icons-react"

import { cn } from "@/lib/utils"
import type { HandbookProposal } from "@/types/serializers"

// A page or an edit Halon proposed, in the handbook's list until someone decides.
export function ProposalItem({ proposal, selected, onSelect }: { proposal: HandbookProposal; selected: boolean; onSelect: (id: string) => void }) {
  function select() {
    onSelect(proposal.id)
  }

  return (
    <li>
      <button
        type="button"
        onClick={select}
        aria-current={selected ? "page" : undefined}
        className={cn("ml-5 flex w-[calc(100%-1.25rem)] items-start gap-2 rounded-md px-2 py-1.5 text-left text-sm text-fg-secondary hover:bg-hover hover:text-fg-primary",
                      selected && "edge-bar bg-hover-2 text-fg-primary")}
      >
        <IconSparkles className="mt-0.5 size-4 shrink-0 text-brand" />
        <span className="flex min-w-0 flex-col">
          <span className="truncate">{proposal.pageTitle}</span>
          <span className="text-xs text-fg-muted">{proposal.newPage ? "New page" : "Edit"}</span>
        </span>
      </button>
    </li>
  )
}
