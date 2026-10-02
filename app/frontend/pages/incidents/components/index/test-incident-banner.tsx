import { IconBrandSlack } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"

export function TestIncidentBanner({ channelUrl }: { channelUrl: string | null | undefined }) {
  return (
    <div className="mb-6 flex flex-col gap-3 edge-bar rounded-xl border border-border bg-info-tint px-5 py-4 [--edge-bar-inset:12px] [--edge-bar:var(--info)] sm:flex-row sm:items-center sm:justify-between">
      <p className="text-sm text-fg-primary">
        Your test channel is ready in Slack. Open it to try the quick actions and post a few messages.
      </p>
      {channelUrl && (
        <Button asChild size="sm" className="shrink-0 gap-1.5">
          <a href={channelUrl}>
            <IconBrandSlack className="size-4" />
            Open the channel
          </a>
        </Button>
      )}
    </div>
  )
}
