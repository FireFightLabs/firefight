import { useState } from "react"
import { usePage } from "@inertiajs/react"

import { cn } from "@/lib/utils"
import { CategoryChip } from "@/pages/setup/components/category-chip"
import { StackCategory } from "@/pages/setup/components/stack-category"
import type { SetupPageProps } from "@/pages/setup/types"

// Every category of integrations, one at a time. Each is answered by connecting at least one tool, or for a category
// Halon can do without, by saying the team does not use one. It opens on the first category still unanswered.
export function StackStep() {
  const { categories, stackAnswers } = usePage<SetupPageProps>().props
  const firstOpen = categories.find((category) => !stackAnswers[category.slug]) ?? categories[0]
  const [ viewing, setViewing ] = useState(firstOpen?.slug)
  // An answer moves the walk on to the next category still unanswered.
  const [ followed, setFollowed ] = useState(firstOpen?.slug)
  if (firstOpen?.slug !== followed) {
    setFollowed(firstOpen?.slug)
    setViewing(firstOpen?.slug)
  }
  const shown = categories.find((category) => category.slug === viewing) ?? firstOpen
  const answered = categories.filter((category) => stackAnswers[category.slug]).length

  if (!shown) {
    return null
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-3">
        <p className="max-w-prose text-sm leading-relaxed text-fg-body">
          Halon works with the tools your team already uses. Go through each kind of tool and connect the ones you have.
          Code, where your apps run and observability are the ones Halon cannot investigate without.
        </p>
        <p className="text-xs text-fg-muted">
          {answered} of {categories.length} answered
        </p>
        <div className="flex h-1.5 gap-1" aria-hidden="true">
          {categories.map((category) => (
            <span
              key={category.slug}
              className={cn("flex-1 rounded-full", stackAnswers[category.slug] ? "bg-brand" : category.slug === shown.slug ? "bg-fg-secondary" : "bg-border-strong")}
            />
          ))}
        </div>
        <ul className="flex flex-wrap gap-1.5" aria-label="Categories">
          {categories.map((category) => (
            <li key={category.slug}>
              <CategoryChip
                category={category}
                answer={stackAnswers[category.slug]}
                selected={category.slug === shown.slug}
                onSelect={setViewing}
              />
            </li>
          ))}
        </ul>
      </div>

      <StackCategory key={shown.slug} category={shown} answer={stackAnswers[shown.slug]} />
    </div>
  )
}
