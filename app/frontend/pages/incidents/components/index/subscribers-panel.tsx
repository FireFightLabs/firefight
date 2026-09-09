import { router } from "@inertiajs/react"

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import type { Incident } from "@/pages/incidents/types"
import { afterMutation } from "@/pages/incidents/lib/after-mutation"
import { incidentSubscriptionPath } from "@/lib/routes"

type Subscriber = Incident["subscribers"][number]

function SubscriberChip({ subscriber }: { subscriber: Subscriber }) {
  const { member } = subscriber

  return (
    <li className="flex min-w-0 items-center gap-2">
      <Avatar className="size-5">
        {member.avatarUrl ? <AvatarImage src={member.avatarUrl} alt={member.name} /> : null}
        <AvatarFallback className="bg-primary/20 text-[10px] font-semibold text-primary">
          {member.initials}
        </AvatarFallback>
      </Avatar>
      <span className="truncate text-[13px] text-foreground">{member.name}</span>
    </li>
  )
}

export function SubscribersPanel({
  subscribers,
  subscribed,
  incidentId,
}: {
  subscribers: Subscriber[]
  subscribed: boolean
  incidentId: string
}) {
  function subscribe() {
    router.post(incidentSubscriptionPath(incidentId), {}, afterMutation("incident", "subscribed"))
  }

  function unsubscribe() {
    router.delete(incidentSubscriptionPath(incidentId), afterMutation("incident", "subscribed"))
  }

  const toggle = subscribed ? unsubscribe : subscribe

  return (
    <div className="rounded-xl border border-border bg-card px-5 py-4">
      <div className="mb-3 flex items-center justify-between">
        <h3 className="text-[12px] font-semibold uppercase tracking-[0.10em] text-foreground">Subscribers</h3>
        <Button type="button" variant="outline" size="xs" onClick={toggle}>
          {subscribed ? "Unsubscribe" : "Subscribe"}
        </Button>
      </div>

      {subscribers.length === 0 ? (
        <p className="text-[13px] text-muted-foreground/70">
          Nobody yet. A subscriber gets every update Firefight posts about this incident as a direct message.
        </p>
      ) : (
        <ul className="flex flex-col gap-2">
          {subscribers.map((subscriber) => (
            <SubscriberChip key={subscriber.id} subscriber={subscriber} />
          ))}
        </ul>
      )}
    </div>
  )
}
