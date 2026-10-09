import type { PackRequest } from "@/types/serializers"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { PackRequestRow } from "@/pages/settings/components/permissions/pack-request-row"

// Packs members asked for after being refused a change, waiting on an admin. Give pack is the same grant as the screen
// makes, in every environment, and each answer confirms with a toast.
export function PackRequestsNotice({ requests, canManage }: { requests: PackRequest[]; canManage: boolean }) {
  if (requests.length === 0) {
    return null
  }

  return (
    <Card className="border-warning-border">
      <CardHeader>
        <CardTitle className="text-base">Waiting for a pack</CardTitle>
        <CardDescription>
          {requests.length === 1 ? "A member was" : `${requests.length} members were`} refused a change and asked for the pack
          that allows it.
        </CardDescription>
      </CardHeader>
      <CardContent className="p-0">
        <div className="divide-border divide-y border-t">
          {requests.map((request) => (
            <PackRequestRow key={request.id} request={request} canManage={canManage} />
          ))}
        </div>
      </CardContent>
    </Card>
  )
}
