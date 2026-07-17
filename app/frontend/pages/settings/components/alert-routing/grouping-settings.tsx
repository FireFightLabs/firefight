import { useForm } from "@inertiajs/react"

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
}: {
  policy: AlertRoutingPolicy
  alertSourceId: string | null
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
        content_match_fields: data.matchFields.split(",").map((f) => f.trim()).filter(Boolean),
      },
    }))
    form.patch(alertRoutingPath(), { onSuccess: () => form.setDefaults() })
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
        <div className="flex flex-wrap items-end gap-4">
          <div className="flex flex-col gap-2">
            <Label htmlFor="grouping-window">Window (minutes)</Label>
            <Input
              id="grouping-window"
              type="number"
              min={MIN_WINDOW_MINUTES}
              max={MAX_WINDOW_MINUTES}
              value={form.data.windowMinutes}
              onChange={(e) => form.setData("windowMinutes", e.target.value)}
              className="w-32"
            />
          </div>
          <div className="flex min-w-64 flex-1 flex-col gap-2">
            <Label htmlFor="grouping-fields">Group by fields</Label>
            <Input
              id="grouping-fields"
              value={form.data.matchFields}
              onChange={(e) => form.setData("matchFields", e.target.value)}
              placeholder="service"
            />
          </div>
          <Button size="sm" onClick={save} disabled={form.processing || !form.isDirty}>
            {form.wasSuccessful && !form.isDirty ? "Saved" : "Save"}
          </Button>
        </div>
        <p className="mt-2 text-xs text-muted-foreground">
          Comma-separated alert fields; two alerts group when all of these values match. 5 minutes to 7 days.
        </p>
        <FormErrors errors={form.errors} className="mt-3" />
      </CardContent>
    </Card>
  )
}
