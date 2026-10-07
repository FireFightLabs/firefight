import { Link } from "@inertiajs/react"
import { IconArrowRight, IconCircleCheck, IconSparkles } from "@tabler/icons-react"

import type { SetupGuide as SetupGuideProps } from "@/pages/agent/types"

// Setup's Meet Halon step, while an admin is on it. It asks for a first question, then once Halon has answered, sends
// the admin back to setup.
export function SetupGuide({ guide }: { guide: SetupGuideProps }) {
  return (
    <div className="mx-3 mt-3 flex flex-col gap-2 rounded-card bg-surface px-3.5 py-3 shadow-card sm:flex-row sm:items-center sm:justify-between">
      <div className="flex items-start gap-2.5">
        {guide.answered ? (
          <IconCircleCheck className="mt-px size-4 shrink-0 text-green" />
        ) : (
          <IconSparkles className="mt-px size-4 shrink-0 text-accent" />
        )}
        <p className="text-[13px] leading-snug text-ink-2">
          <span className="font-medium text-ink">Meet Halon. </span>
          {guide.answered
            ? "Halon answered your first question, so this step of setup is done."
            : "Send the question below, or ask your own. Setup goes on once Halon answers."}
        </p>
      </div>
      <Link
        href={guide.setupPath}
        className={`inline-flex shrink-0 items-center gap-1.5 self-end rounded-full px-3 py-1.5 text-[13px] font-medium transition-colors duration-150 sm:self-auto ${
          guide.answered ? "bg-primary text-primary-foreground hover:bg-[var(--btn-primary-hover)]" : "text-ink-2 hover:bg-hover hover:text-ink"
        }`}
      >
        {guide.answered ? "Back to setup" : "Setup"}
        <IconArrowRight className="size-3.5" />
      </Link>
    </div>
  )
}
