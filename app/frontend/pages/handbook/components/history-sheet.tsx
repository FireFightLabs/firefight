import { MarkdownText } from "@/components/markdown-text"
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { formatDateTime } from "@/lib/formatters"
import { HANDBOOK_PAGE_KINDS } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import type { HandbookPage } from "@/types/serializers"

interface HistorySheetProps {
  page: HandbookPage | null
  onClose: () => void
}

// A page's earlier wordings, newest first, each with who wrote it and when. A synced page's came from its source.
export function HistorySheet({ page, onClose }: HistorySheetProps) {
  const nobody = page?.kind === HANDBOOK_PAGE_KINDS.SYNCED ? "Synced from its source" : "Written with an API key"
  return (
    <Sheet open={page !== null} onOpenChange={whenClosed(onClose)}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>History of {page?.title}</SheetTitle>
          <SheetDescription>Every earlier wording is kept, newest first.</SheetDescription>
        </SheetHeader>
        <ol className="flex flex-col gap-6 px-4 pb-6">
          {page?.history.map(([ id, writtenAt, writtenBy, text ]) => (
            <li key={id} className="flex flex-col gap-2 border-l border-border pl-4">
              <span className="text-xs text-muted-foreground">
                {writtenBy || nobody}, {formatDateTime(writtenAt)}
              </span>
              <MarkdownText text={text || "Empty"} className="text-fg-muted" />
            </li>
          ))}
        </ol>
      </SheetContent>
    </Sheet>
  )
}
