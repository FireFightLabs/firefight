import { buildStory } from "@/components/investigations/story"
import { StoryEntryRow } from "@/components/investigations/story-entry-row"
import type { InvestigationDetail } from "@/types/serializers"

// What it was asked, every step it took, the theories as it formed and settled them, and how it ended.
export function RunStory({ investigation }: { investigation: InvestigationDetail }) {
  const story = buildStory(investigation)

  return (
    <ol className="relative">
      {story.map((entry, index) => (
        <StoryEntryRow key={entry.key} entry={entry} investigation={investigation} connected={index < story.length - 1} />
      ))}
    </ol>
  )
}
