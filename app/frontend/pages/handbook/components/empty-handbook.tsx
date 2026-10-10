import { IconFileImport, IconPlus, IconSparkles } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { SuggestionCard } from "@/pages/handbook/components/suggestion-card"
import type { HandbookSuggestion } from "@/types/serializers"

interface EmptyHandbookProps {
  suggestions: HandbookSuggestion[]
  canWrite: boolean
  canDraft: boolean
  canImport: boolean
  drafting: boolean
  onStart: (suggestion: HandbookSuggestion | null) => void
  onDraft: () => void
  onImport: () => void
}

// A handbook with no pages yet says what it is for, offers three ways to start, and suggests the pages most teams write first.
export function EmptyHandbook({ suggestions, canWrite, canDraft, canImport, drafting, onStart, onDraft, onImport }: EmptyHandbookProps) {
  function startBlank() {
    onStart(null)
  }

  return (
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-8 py-4">
      <div className="flex flex-col gap-2">
        <h2 className="text-xl font-semibold tracking-tight text-fg-headline">Write down how your workspace works</h2>
        <p className="max-w-2xl text-sm text-muted-foreground">
          Halon reads the handbook at the start of every chat and investigation and follows it. Start from a page below, let
          Halon draft pages from what it can see, or bring in docs you already keep.
        </p>
      </div>
      <div className="flex flex-wrap gap-2">
        {canDraft && canWrite && (
          <Button type="button" size="sm" onClick={onDraft} disabled={drafting}>
            <IconSparkles className="size-4" />
            {drafting ? "Starting…" : "Draft with Halon"}
          </Button>
        )}
        {canWrite && canImport && (
          <Button type="button" size="sm" variant="outline" onClick={onImport}>
            <IconFileImport className="size-4" />
            Import docs
          </Button>
        )}
        {canWrite && (
          <Button type="button" size="sm" variant="outline" onClick={startBlank}>
            <IconPlus className="size-4" />
            Blank page
          </Button>
        )}
      </div>
      <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {suggestions.map((suggestion) => (
          <li key={suggestion.title}>
            <SuggestionCard suggestion={suggestion} canWrite={canWrite} onStart={onStart} />
          </li>
        ))}
      </ul>
    </div>
  )
}
