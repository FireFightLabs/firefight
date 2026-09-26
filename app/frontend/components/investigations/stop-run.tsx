import { router } from "@inertiajs/react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import { investigationStopPath } from "@/lib/routes"

// Ends a run from its story, as Slack's own stop does from its thread. The run finishes the step it is on first.
export function StopRun({ investigationId }: { investigationId: string }) {
  const [ stopping, setStopping ] = useState(false)

  function stop() {
    setStopping(true)
    router.post(investigationStopPath(investigationId), {}, { preserveScroll: true, onFinish: () => setStopping(false) })
  }

  return (
    <Button type="button" size="sm" variant="outline" disabled={stopping} onClick={stop}>
      {stopping ? "Stopping" : "Stop"}
    </Button>
  )
}
