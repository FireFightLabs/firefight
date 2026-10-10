import { router } from "@inertiajs/react"
import type { DragEndEvent } from "@dnd-kit/core"
import { IconChevronLeft, IconFileImport, IconPlus, IconSparkles } from "@tabler/icons-react"
import { useCallback, useEffect, useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { useOptimisticOrder } from "@/hooks/use-optimistic-order"
import { HANDBOOK_PAGE_KINDS, HANDBOOK_PAGE_QUERY, HANDBOOK_PROPOSAL_QUERY } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { replaceQuery } from "@/lib/query"
import { draftHandbookPath, handbookPagePath, handbookSourcePath, reorderHandbookPagesPath, syncHandbookSourcePath } from "@/lib/routes"
import { DiscardChangesDialog } from "@/pages/handbook/components/discard-changes-dialog"
import { EmptyHandbook } from "@/pages/handbook/components/empty-handbook"
import { HistorySheet } from "@/pages/handbook/components/history-sheet"
import { ImportDialog } from "@/pages/handbook/components/import-dialog"
import { PageForm } from "@/pages/handbook/components/page-form"
import { PageList } from "@/pages/handbook/components/page-list"
import { PageView } from "@/pages/handbook/components/page-view"
import { ProposalView } from "@/pages/handbook/components/proposal-view"
import { useUnsavedChanges } from "@/pages/handbook/hooks/use-unsaved-changes"
import { type HandbookPageProps, NOTHING_SELECTED, type Selection } from "@/pages/handbook/types"
import type { HandbookPage, HandbookSource, HandbookSuggestion } from "@/types/serializers"

const IN_PLACE = { preserveScroll: true }

function selectionFromUrl(): Selection {
  const params = new URLSearchParams(window.location.search)
  const page = params.get(HANDBOOK_PAGE_QUERY)
  const proposal = params.get(HANDBOOK_PROPOSAL_QUERY)
  if (page) {
    return { kind: "page", id: page }
  }
  return proposal ? { kind: "proposal", id: proposal } : NOTHING_SELECTED
}

type HandbookScreenProps = Pick<HandbookPageProps, "pages" | "suggestions" | "directingRole" | "proposals" | "sources" | "roles" | "timeZones" | "importers">

// The handbook lists its pages on the left in the order Halon reads them, and reads, edits or decides on the chosen one
// on the right. Below 48rem it shows one side at a time.
export function HandbookScreen({ pages, suggestions, directingRole, proposals, sources, roles, timeZones, importers }: HandbookScreenProps) {
  const canWrite = useCan("handbook")
  const canDraft = useCan("investigations")
  const [ selection, setSelection ] = useState<Selection>(selectionFromUrl)
  const [ editing, setEditing ] = useState(false)
  const [ dirty, setDirty ] = useState(false)
  const [ deleting, setDeleting ] = useState<HandbookPage | null>(null)
  const [ stopping, setStopping ] = useState<HandbookSource | null>(null)
  const [ history, setHistory ] = useState<HandbookPage | null>(null)
  const [ importing, setImporting ] = useState(false)
  const [ drafting, setDrafting ] = useState(false)
  const unsaved = useUnsavedChanges(dirty)
  const { ordered, onDragEnd } = useOptimisticOrder(pages)

  const page = selection.kind === "page" ? pages.find((each) => each.id === selection.id) ?? null : null
  const proposal = selection.kind === "proposal" ? proposals.find((each) => each.id === selection.id) ?? null : null
  const pageSource = page?.sourceId ? sources.find((source) => source.id === page.sourceId) ?? null : null
  const directingSuggestion = pages.some((each) => each.kind === HANDBOOK_PAGE_KINDS.DIRECTING) ? null : suggestions.find((each) => each.takesRole) ?? null
  const showingForm = selection.kind === "new" || (editing && page !== null)
  const empty = pages.length === 0 && proposals.length === 0 && sources.length === 0
  // Something to read on the right. Wide screens open the first page when nothing is chosen.
  const shownPage = page ?? (selection.kind === "none" ? ordered[0] ?? null : null)

  // A link Halon cited opens at its section once the page has drawn.
  useEffect(() => {
    if (window.location.hash) {
      document.getElementById(decodeURIComponent(window.location.hash.slice(1)))?.scrollIntoView({ block: "start" })
    }
  }, [])

  const trackDirty = useCallback((value: boolean) => setDirty(value), [])

  function choose(next: Selection) {
    unsaved.guard(() => {
      setEditing(false)
      setDirty(false)
      setSelection(next)
      replaceQuery({
        [HANDBOOK_PAGE_QUERY]: next.kind === "page" ? next.id : null,
        [HANDBOOK_PROPOSAL_QUERY]: next.kind === "proposal" ? next.id : null,
      })
    })
  }

  function selectPage(id: string) {
    choose({ kind: "page", id })
  }

  function selectProposal(id: string) {
    choose({ kind: "proposal", id })
  }

  function start(suggestion: HandbookSuggestion | null) {
    choose({ kind: "new", suggestion })
  }

  function startBlank() {
    start(null)
  }

  function backToList() {
    choose(NOTHING_SELECTED)
  }

  function edit() {
    if (shownPage) {
      setSelection({ kind: "page", id: shownPage.id })
      setEditing(true)
    }
  }

  function stopEditing() {
    unsaved.guard(() => {
      setEditing(false)
      setDirty(false)
      if (selection.kind === "new") {
        setSelection(NOTHING_SELECTED)
      }
    })
  }

  // A saved page opens where the server sent it, which for a new page is its own address.
  function saved() {
    setDirty(false)
    setEditing(false)
    setSelection(selectionFromUrl())
  }

  function submitOrder(orderedIds: string[], onFailure: () => void) {
    router.patch(reorderHandbookPagesPath(), { ordered_ids: orderedIds }, { ...IN_PLACE, onError: onFailure })
  }

  function reorder(event: DragEndEvent) {
    onDragEnd(event, submitOrder)
  }

  function askDelete() {
    setDeleting(shownPage)
  }

  function cancelDelete() {
    setDeleting(null)
  }

  function confirmDelete() {
    if (deleting) {
      router.delete(handbookPagePath(deleting.id), { onFinish: cancelDelete, onSuccess: backToList })
    }
  }

  function showHistory() {
    setHistory(shownPage)
  }

  function hideHistory() {
    setHistory(null)
  }

  function sync(source: HandbookSource) {
    router.post(syncHandbookSourcePath(source.id), {}, IN_PLACE)
  }

  function cancelStop() {
    setStopping(null)
  }

  function confirmStop() {
    if (stopping) {
      router.delete(handbookSourcePath(stopping.id), { ...IN_PLACE, onFinish: cancelStop })
    }
  }

  function openImport() {
    setImporting(true)
  }

  function closeImport() {
    setImporting(false)
  }

  function doneDrafting() {
    setDrafting(false)
  }

  function draft() {
    unsaved.guard(() => {
      setDrafting(true)
      router.post(draftHandbookPath(), {}, { onFinish: doneDrafting })
    })
  }

  const detail = showingForm ? (
    <PageForm
      key={selection.kind === "new" ? `new-${selection.suggestion?.title ?? "blank"}` : page?.id}
      page={selection.kind === "new" ? null : page}
      suggestion={selection.kind === "new" ? selection.suggestion : null}
      roles={roles}
      timeZones={timeZones}
      directingRoleName={directingRole}
      onDirtyChange={trackDirty}
      onCancel={stopEditing}
      onSaved={saved}
    />
  ) : proposal ? (
    <ProposalView key={proposal.id} proposal={proposal} canDecide={canWrite} />
  ) : shownPage ? (
    <PageView page={shownPage} source={pageSource} canWrite={canWrite} onEdit={edit} onHistory={showHistory} onDelete={askDelete} onSync={sync} />
  ) : (
    <p className="text-sm text-muted-foreground">{selection.kind === "none" ? "Choose a page to read it." : "That page is no longer in the handbook."}</p>
  )
  const detailOpen = selection.kind !== "none"
  const listSelection: Selection = page || !shownPage ? selection : { kind: "page", id: shownPage.id }

  return (
    <>
      <div className="flex flex-col gap-4 px-4 py-4 md:py-6 lg:px-6">
        {!empty && (
          <div className="flex flex-wrap items-center justify-between gap-3">
            <p className="max-w-2xl text-sm text-muted-foreground">How this workspace works, page by page. Halon reads it at the start of every chat and investigation.</p>
            {canWrite && (
              <div className="flex flex-wrap gap-2">
                {canDraft && (
                  <Button type="button" size="sm" variant="outline" onClick={draft} disabled={drafting}>
                    <IconSparkles className="size-4" />
                    {drafting ? "Starting…" : "Draft with Halon"}
                  </Button>
                )}
                {importers.length > 0 && (
                  <Button type="button" size="sm" variant="outline" onClick={openImport}>
                    <IconFileImport className="size-4" />
                    Import docs
                  </Button>
                )}
                <Button type="button" size="sm" onClick={startBlank}>
                  <IconPlus className="size-4" />
                  Add page
                </Button>
              </div>
            )}
          </div>
        )}
        {empty && selection.kind !== "new" ? (
          <EmptyHandbook suggestions={suggestions} canWrite={canWrite} canDraft={canDraft} canImport={importers.length > 0} drafting={drafting}
                         onStart={start} onDraft={draft} onImport={openImport} />
        ) : (
          <div className="grid gap-6 md:grid-cols-[16rem_minmax(0,1fr)] lg:grid-cols-[18rem_minmax(0,1fr)]">
            <aside className={detailOpen ? "hidden md:block" : "block"}>
              <div className="md:sticky md:top-20">
                <PageList pages={ordered} proposals={proposals} sources={sources} selection={listSelection}
                          canWrite={canWrite} directingRole={directingRole} directingSuggestion={directingSuggestion}
                          onDragEnd={reorder} onSelectPage={selectPage} onSelectProposal={selectProposal} onStart={start} onSync={sync} onStop={setStopping} />
              </div>
            </aside>
            <main className={detailOpen ? "block min-w-0" : "hidden min-w-0 md:block"}>
              <Button type="button" variant="ghost" size="sm" className="mb-3 -ml-2 md:hidden" onClick={backToList}>
                <IconChevronLeft className="size-4" />
                All pages
              </Button>
              <div className="rounded-lg border bg-surface-card p-5 md:p-6">{detail}</div>
            </main>
          </div>
        )}
      </div>
      <ImportDialog open={importing} importers={importers} onClose={closeImport} />
      <HistorySheet page={history} onClose={hideHistory} />
      <DiscardChangesDialog open={unsaved.confirming} onDiscard={unsaved.discard} onKeepEditing={unsaved.keepEditing} />
      <ConfirmDeleteDialog
        open={deleting !== null}
        title={`Delete ${deleting?.title ?? "this page"}?`}
        description={`Halon stops following it at once, and its ${deleting?.history.length ? `${deleting.history.length + 1} wordings are` : "wording is"} deleted with it.`}
        confirmLabel="Delete page"
        onConfirm={confirmDelete}
        onCancel={cancelDelete}
      />
      <ConfirmDeleteDialog
        open={stopping !== null}
        title={`Stop syncing ${stopping?.label ?? "this source"}?`}
        description={`Its ${stopping?.pageCount === 1 ? "page is" : `${stopping?.pageCount ?? 0} pages are`} removed from the handbook, and Halon stops following ${stopping?.pageCount === 1 ? "it" : "them"}. The source itself is not touched.`}
        confirmLabel="Stop syncing"
        onConfirm={confirmStop}
        onCancel={cancelStop}
      />
    </>
  )
}
