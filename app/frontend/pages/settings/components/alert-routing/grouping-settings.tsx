import { useForm } from "@inertiajs/react"
import { toast } from "sonner"

import type { AlertRoutingPolicy } from "@/types/serializers"
import { alertRoutingPath } from "@/lib/routes"
import { FormErrors } from "@/pages/settings/components/form-errors"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

const MIN_WINDOW_MINUTES = 5
const MAX_WINDOW_MINUTES = 10080

export function GroupingSettings({
  policy,
  alertSourceId,
  canManage,
}: {
  policy: AlertRoutingPolicy
  alertSourceId: string | null
  canManage: boolean
}) {
  const form = useForm({
    windowMinutes: String(policy.groupingWindowMinutes),
    matchFields: policy.contentMatchFields.join(", "),
  })

  function save() {
    form.transform((data) => ({
      alert_source_id: alertSourceId,
      policy: {
        grouping_window_minutes: Number(data.windowMinutes),
        content_match_fields: data.matchFields.split(",").map((field) => field.trim()).filter(Boolean),
      },
    }))
    form.patch(alertRoutingPath(), {
      onSuccess: () => {
        form.setDefaults()
        toast.success("Grouping settings saved")
      },
    })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Grouping</CardTitle>
        <CardDescription className="mt-1">
          Alerts whose grouping fields match within the window attach to the same incident instead of
          creating new ones.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {canManage ? (
          <div className="flex flex-wrap items-end gap-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="grouping-window">Window (minutes)</Label>
              <Input
                id="grouping-window"
                type="number"
                min={MIN_WINDOW_MINUTES}
                max={MAX_WINDOW_MINUTES}
                value={form.data.windowMinutes}
                onChange={(event) => form.setData("windowMinutes", event.target.value)}
                className="w-32"
              />
            </div>
            <div className="flex min-w-64 flex-1 flex-col gap-2">
              <Label htmlFor="grouping-fields">Group by fields</Label>
              <Input
                id="grouping-fields"
                value={form.data.matchFields}
                onChange={(event) => form.setData("matchFields", event.target.value)}
                placeholder="service"
              />
            </div>
            <Button size="sm" onClick={save} disabled={form.processing || !form.isDirty}>
              Save
            </Button>
          </div>
        ) : (
          <div className="flex flex-wrap gap-8 text-sm">
            <div className="flex flex-col gap-1">
              <span className="text-xs font-medium text-muted-foreground">Window (minutes)</span>
              <span className="tabular-nums">{policy.groupingWindowMinutes}</span>
            </div>
            <div className="flex flex-col gap-1">
              <span className="text-xs font-medium text-muted-foreground">Group by fields</span>
              <span>{policy.contentMatchFields.length > 0 ? policy.contentMatchFields.join(", ") : "-"}</span>
            </div>
          </div>
        )}
        <p className="mt-2 text-xs text-muted-foreground">
          Comma-separated alert fields. Two alerts group when all of these values match. 5 minutes to 7 days.
        </p>
        {canManage && <FormErrors errors={form.errors} className="mt-3" />}
      </CardContent>
    </Card>
  )
}
