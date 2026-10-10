import type { SharedProps } from "@/types"
import type { HandbookImporter, HandbookPage, HandbookProposal, HandbookRole, HandbookSource, HandbookSuggestion } from "@/types/serializers"

export interface HandbookPageProps extends SharedProps {
  [key: string]: unknown
  pages: HandbookPage[]
  suggestions: HandbookSuggestion[]
  directingRole: string | null
  proposals: HandbookProposal[]
  sources: HandbookSource[]
  roles: HandbookRole[]
  // Every time zone a freeze window can be read in.
  timeZones: string[]
  importers: HandbookImporter[]
}

// The right side shows a page, a proposal, or the form for a new page, which may start from a suggestion.
export type Selection =
  | { kind: "page"; id: string }
  | { kind: "proposal"; id: string }
  | { kind: "new"; suggestion: HandbookSuggestion | null }
  | { kind: "none" }

export const NOTHING_SELECTED: Selection = { kind: "none" }
