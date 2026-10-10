import { closestCenter, DndContext, type DragEndEvent, PointerSensor, KeyboardSensor, useSensor, useSensors } from "@dnd-kit/core"
import { restrictToVerticalAxis } from "@dnd-kit/modifiers"
import { SortableContext, sortableKeyboardCoordinates, verticalListSortingStrategy } from "@dnd-kit/sortable"
import { IconUserStar } from "@tabler/icons-react"

import { PageListGroup } from "@/pages/handbook/components/page-list-group"
import { ProposalItem } from "@/pages/handbook/components/proposal-item"
import { SortablePageItem } from "@/pages/handbook/components/sortable-page-item"
import { SourceItem } from "@/pages/handbook/components/source-item"
import type { Selection } from "@/pages/handbook/types"
import type { HandbookPage, HandbookProposal, HandbookSource, HandbookSuggestion } from "@/types/serializers"

interface PageListProps {
  pages: HandbookPage[]
  proposals: HandbookProposal[]
  sources: HandbookSource[]
  selection: Selection
  canWrite: boolean
  directingRole: string | null
  // Offered when no page says who directs Halon yet.
  directingSuggestion: HandbookSuggestion | null
  onDragEnd: (event: DragEndEvent) => void
  onSelectPage: (id: string) => void
  onSelectProposal: (id: string) => void
  onStart: (suggestion: HandbookSuggestion) => void
  onSync: (source: HandbookSource) => void
  onStop: (source: HandbookSource) => void
}

// The handbook's contents, with what Halon proposed and waits on a person first, then the pages in the order Halon
// reads them, then where synced pages come from.
export function PageList({
  pages, proposals, sources, selection, canWrite, directingRole, directingSuggestion, onDragEnd, onSelectPage, onSelectProposal, onStart, onSync, onStop,
}: PageListProps) {
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }), useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }))

  function startDirecting() {
    if (directingSuggestion) {
      onStart(directingSuggestion)
    }
  }

  return (
    <nav aria-label="Handbook pages" className="flex flex-col gap-6">
      {proposals.length > 0 && (
        <PageListGroup title={`Waiting for review (${proposals.length})`}>
          {proposals.map((proposal) => (
            <ProposalItem key={proposal.id} proposal={proposal} selected={selection.kind === "proposal" && selection.id === proposal.id} onSelect={onSelectProposal} />
          ))}
        </PageListGroup>
      )}
      <PageListGroup title="Pages">
        <DndContext sensors={sensors} collisionDetection={closestCenter} modifiers={[ restrictToVerticalAxis ]} onDragEnd={onDragEnd}>
          <SortableContext items={pages.map((page) => page.id)} strategy={verticalListSortingStrategy}>
            {pages.map((page) => (
              <SortablePageItem key={page.id} page={page} sortable={canWrite && pages.length > 1}
                                selected={selection.kind === "page" && selection.id === page.id} onSelect={onSelectPage} />
            ))}
          </SortableContext>
        </DndContext>
        {directingSuggestion && (
          <li>
            <button
              type="button"
              onClick={startDirecting}
              disabled={!canWrite}
              className="ml-5 flex w-[calc(100%-1.25rem)] items-start gap-2 rounded-md px-2 py-1.5 text-left text-sm text-fg-muted hover:bg-hover hover:text-fg-primary disabled:hover:bg-transparent"
            >
              <IconUserStar className="mt-0.5 size-4 shrink-0" />
              <span className="flex flex-col">
                <span>{directingSuggestion.title}</span>
                <span className="text-xs">{directingRole ?? "The Incident Lead"}, by default</span>
              </span>
            </button>
          </li>
        )}
      </PageListGroup>
      {sources.length > 0 && (
        <PageListGroup title="Synced from">
          {sources.map((source) => (
            <SourceItem key={source.id} source={source} canWrite={canWrite} onSync={onSync} onStop={onStop} />
          ))}
        </PageListGroup>
      )}
    </nav>
  )
}
