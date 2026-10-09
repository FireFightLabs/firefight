import { IconRefresh } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { redeliverOperatorWebhookDeliveryPath } from "@/lib/routes"
import { useAction } from "@/pages/operator/hooks/use-action"

export function RedeliverButton({ deliveryId }: { deliveryId: string }) {
  const { busy, post } = useAction()

  function redeliver() {
    post(redeliverOperatorWebhookDeliveryPath(deliveryId))
  }

  return (
    <Button type="button" size="sm" variant="outline" onClick={redeliver} disabled={busy}>
      <IconRefresh className="size-3.5" />
      Send again
    </Button>
  )
}
