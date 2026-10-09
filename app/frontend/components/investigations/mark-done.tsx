import { router } from "@inertiajs/react"
import { IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import { investigationFixStepDonePath } from "@/lib/routes"
import type { InvestigationRemediationStep } from "@/types/serializers"

// A step a person does rather than Firefight, done once they say so.
export function MarkDone({ investigationId, step }: { investigationId: string; step: InvestigationRemediationStep }) {
  const [ marking, setMarking ] = useState(false)

  function markDone() {
    setMarking(true)
    router.post(investigationFixStepDonePath(investigationId, step.id), {}, { preserveScroll: true, onFinish: () => setMarking(false) })
  }

  return (
    <Button type="button" size="sm" variant="outline" className="w-fit" disabled={marking} onClick={markDone}>
      {marking && <IconLoader2 className="motion-safe:animate-spin" />}
      {marking ? "Marking done" : "Mark done"}
    </Button>
  )
}
