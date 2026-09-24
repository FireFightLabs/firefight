import { InvestigationStory, investigationTitle } from "@/components/investigations/investigation-story"
import { useLiveInvestigation } from "@/components/investigations/use-live-investigation"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { whenClosed } from "@/lib/handlers"
import type { InvestigationDetail } from "@/types/serializers"

interface InvestigationSheetProps {
  investigation: InvestigationDetail | null
  // The page prop that holds the run, which a live run reloads.
  prop: string
  onClose: () => void
  onDeclare?: () => void
}

// A run read over the page it belongs to, its incident or the chat that asked for it.
export function InvestigationSheet({ investigation, prop, onClose, onDeclare }: InvestigationSheetProps) {
  useLiveInvestigation(investigation?.status, prop)

  return (
    <Sheet open={investigation != null} onOpenChange={whenClosed(onClose)}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-2xl">
        {investigation && (
          <div className="px-6 py-8">
            <SheetDescription className="sr-only">What Halon was asked, what it found and every step it took.</SheetDescription>
            <InvestigationStory
              investigation={investigation}
              onDeclare={onDeclare}
              title={<SheetTitle className="text-2xl font-semibold tracking-tight text-balance">{investigationTitle(investigation)}</SheetTitle>}
            />
          </div>
        )}
      </SheetContent>
    </Sheet>
  )
}
