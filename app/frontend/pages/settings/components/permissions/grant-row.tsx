import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconTrash } from "@tabler/icons-react"

import type { EnvironmentOption, Principal } from "@/types/serializers"
import { abilityGrantPath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { RISK_VARIANT } from "@/pages/settings/components/permissions/risk"
import { formatDate } from "@/lib/formatters"

type Grant = Principal["grants"][number]

export function GrantRow({
  grant,
  environments,
  canManage,
}: {
  grant: Grant
  environments: EnvironmentOption[]
  canManage: boolean
}) {
  const [open, setOpen] = useState(false)
  const [expiryOpen, setExpiryOpen] = useState(false)
  const scoped = environments.filter((environment) => grant.environmentIds.includes(environment.id))
  const label = scoped.length === 0 ? "All environments" : scoped.map((environment) => environment.name).join(", ")
  const expiryLabel = grant.expiresAt
    ? `${grant.expired ? "Expired" : "Until"} ${formatDate(grant.expiresAt)}`
    : "No expiry"

  function retarget(environmentId: string) {
    const next = grant.environmentIds.includes(environmentId)
      ? grant.environmentIds.filter((id) => id !== environmentId)
      : [...grant.environmentIds, environmentId]

    router.patch(abilityGrantPath(grant.id), { environment_ids: next }, { preserveScroll: true })
  }

  // The environment scope rides along because an absent environment_ids reads
  // as "no environments", which would silently widen the grant.
  function reschedule(value: string) {
    router.patch(
      abilityGrantPath(grant.id),
      { environment_ids: grant.environmentIds, expires_at: value },
      { preserveScroll: true, onSuccess: () => setExpiryOpen(false) },
    )
  }

  return (
    <div className="flex items-center justify-between gap-3 px-3 py-2.5">
      <div className="flex min-w-0 items-center gap-2">
        {grant.kind === "set" ? (
          <>
            <span className="min-w-0 truncate text-sm font-medium">{grant.label}</span>
            <Badge variant="outline" className="shrink-0">
              set of {grant.actionCount}
            </Badge>
          </>
        ) : (
          <>
            <code className="min-w-0 truncate text-xs">{grant.label}</code>
            <Badge variant={RISK_VARIANT[grant.riskLevel ?? ""] ?? "secondary"} className="shrink-0">
              {grant.riskLevel}
            </Badge>
          </>
        )}
        {grant.expired && (
          <Badge variant="outline" className="text-muted-foreground shrink-0">
            Expired
          </Badge>
        )}
      </div>
      <div className="flex shrink-0 items-center gap-1">
        {canManage && environments.length > 0 ? (
          <Popover open={open} onOpenChange={setOpen}>
            <PopoverTrigger asChild>
              <Button variant="outline" size="sm" className="h-8 font-normal">
                {label}
              </Button>
            </PopoverTrigger>
            <PopoverContent align="end" className="w-56">
              <p className="text-muted-foreground mb-2 text-xs">
                Untick everything for all environments.
              </p>
              <div className="flex flex-col gap-2">
                {environments.map((environment) => (
                  <label key={environment.id} className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={grant.environmentIds.includes(environment.id)}
                      onCheckedChange={() => retarget(environment.id)}
                    />
                    {environment.name}
                  </label>
                ))}
              </div>
            </PopoverContent>
          </Popover>
        ) : (
          <Badge variant="outline">{label}</Badge>
        )}
        {canManage ? (
          <Popover open={expiryOpen} onOpenChange={setExpiryOpen}>
            <PopoverTrigger asChild>
              <Button variant="outline" size="sm" className="h-8 font-normal">
                {expiryLabel}
              </Button>
            </PopoverTrigger>
            <PopoverContent align="end" className="w-64">
              <div className="flex flex-col gap-2">
                <Label htmlFor={`grant-expiry-${grant.id}`} className="text-xs">
                  Expires
                </Label>
                <Input
                  id={`grant-expiry-${grant.id}`}
                  type="date"
                  defaultValue={grant.expiresAt?.slice(0, 10) ?? ""}
                  onChange={(event) => reschedule(event.target.value)}
                />
                <p className="text-muted-foreground text-xs">
                  Clear the date to grant indefinitely.
                </p>
              </div>
            </PopoverContent>
          </Popover>
        ) : (
          grant.expiresAt && <Badge variant="outline">{expiryLabel}</Badge>
        )}
        {canManage && (
          <Button
            variant="ghost"
            size="icon"
            className="text-muted-foreground hover:text-destructive size-8"
            aria-label={`Revoke ${grant.label}`}
            onClick={() => router.delete(abilityGrantPath(grant.id), { preserveScroll: true })}
          >
            <IconTrash className="size-4" />
          </Button>
        )}
      </div>
    </div>
  )
}
