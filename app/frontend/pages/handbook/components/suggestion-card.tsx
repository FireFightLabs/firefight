import { Button } from "@/components/ui/button"
import type { HandbookSuggestion } from "@/types/serializers"

// A page most teams write first, with what belongs in it and an example.
export function SuggestionCard({ suggestion, canWrite, onStart }: { suggestion: HandbookSuggestion; canWrite: boolean; onStart: (suggestion: HandbookSuggestion) => void }) {
  function start() {
    onStart(suggestion)
  }

  return (
    <div className="flex h-full flex-col gap-2 rounded-lg border bg-surface-card p-4">
      <h3 className="text-sm font-semibold text-fg-primary">{suggestion.title}</h3>
      <p className="text-sm text-muted-foreground">{suggestion.hint}</p>
      <p className="text-xs text-fg-muted italic">{suggestion.example}</p>
      {canWrite && (
        <Button type="button" size="sm" variant="outline" className="mt-auto w-fit" onClick={start}>
          Write this page
        </Button>
      )}
    </div>
  )
}
