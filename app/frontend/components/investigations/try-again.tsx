import { router } from "@inertiajs/react"
import { IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import { investigationFixStepRetryPath } from "@/lib/routes"
import type { InvestigationRemediationStep } from "@/types/serializers"

// A step that failed, run again as whoever applied the fix, the same as Try again in Slack. The server says why whoever
// is looking cannot press it.
export function TryAgain({ investigationId, step }: { investigationId: string; step: InvestigationRemediationStep }) {
  const [ sending, setSending ] = useState(false)

  function tryAgain() {
    setSending(true)
    router.post(investigationFixStepRetryPath(investigationId, step.id), {}, { preserveScroll: true, onFinish: () => setSending(false) })
  }

  return (
    <div className="flex flex-col gap-1">
      <Button type="button" size="sm" variant="outline" className="w-fit" disabled={step.retryBlockedReason != null || sending} onClick={tryAgain}>
        {sending && <IconLoader2 className="motion-safe:animate-spin" />}
        {sending ? "Trying again" : "Try again"}
      </Button>
      {step.retryBlockedReason && <span className="text-xs text-fg-muted">{step.retryBlockedReason}</span>}
    </div>
  )
}
