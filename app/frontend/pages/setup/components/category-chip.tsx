import { IconCheck, IconMinus } from "@tabler/icons-react"

import { SETUP_ANSWERS } from "@/lib/generated/constants"
import { cn } from "@/lib/utils"
import type { OnboardingCategory } from "@/types/serializers"

// One category of the stack walk, marked once it is connected or said to be unused.
export function CategoryChip({
  category,
  answer,
  selected,
  onSelect,
}: {
  category: OnboardingCategory
  answer: string | undefined
  selected: boolean
  onSelect: (slug: string) => void
}) {
  function select() {
    onSelect(category.slug)
  }

  return (
    <button
      type="button"
      onClick={select}
      aria-pressed={selected}
      className={cn(
        "flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs transition-colors duration-150",
        selected ? "border-brand-border bg-brand-tint text-fg-primary" : "border-border text-fg-secondary hover:bg-surface-hover hover:text-fg-primary",
      )}
    >
      {answer === SETUP_ANSWERS.CONNECTED && <IconCheck className="size-3 text-brand" stroke={3} aria-label="Connected" />}
      {answer === SETUP_ANSWERS.UNUSED && <IconMinus className="size-3 text-fg-muted" aria-label="Not used" />}
      {category.name}
    </button>
  )
}
