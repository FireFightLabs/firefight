import { Link, usePage } from "@inertiajs/react"
import { IconAlertTriangle, IconMessageCircle } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { SETUP_STEP_STATES } from "@/lib/generated/constants"
import { agentChatsPath } from "@/lib/routes"
import type { SetupPageProps } from "@/pages/setup/types"
import type { OnboardingStep } from "@/types/serializers"

// The first chat happens in the real chat, which starts with this question in the box. The step is done once Halon
// has answered, and the chat offers the way back here. While Halon cannot answer yet, the step says why and waits.
export function HalonStep({ step }: { step: OnboardingStep }) {
  const { firstQuestion } = usePage<SetupPageProps>().props
  const answered = step.state === SETUP_STEP_STATES.DONE
  const holdingReason = answered ? null : step.note

  return (
    <div className="flex flex-col gap-6">
      <p className="max-w-prose text-sm leading-relaxed text-fg-body">
        {answered
          ? "Halon answered your first question. Ask it anything about your stack from Chat whenever you like."
          : "Halon is the AI that investigates incidents with the tools you connected. Ask it a first question to see how it works. Here is one to start with, built from what you connected."}
      </p>

      {!answered && (
        <blockquote className="border-border flex items-start gap-3 rounded-lg border bg-surface-card px-4 py-3.5 text-sm text-fg-primary">
          <IconMessageCircle className="mt-0.5 size-4 shrink-0 text-brand" />
          <span>{firstQuestion}</span>
        </blockquote>
      )}

      {holdingReason && (
        <p className="flex items-start gap-2.5 rounded-lg border border-warning-border bg-warning-tint px-4 py-3 text-sm text-fg-primary">
          <IconAlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" />
          <span>{holdingReason} Change it under Choose Halon&apos;s AI.</span>
        </p>
      )}

      <div className="flex justify-end border-t border-border pt-5">
        {holdingReason ? (
          <Button disabled>Ask Halon</Button>
        ) : (
          <Button asChild variant={answered ? "outline" : "default"}>
            <Link href={agentChatsPath()}>{answered ? "Open Chat" : "Ask Halon"}</Link>
          </Button>
        )}
      </div>
    </div>
  )
}
