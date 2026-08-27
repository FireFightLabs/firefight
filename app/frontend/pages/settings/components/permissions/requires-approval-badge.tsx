import { IconShieldCheck } from "@tabler/icons-react"

import { Badge } from "@/components/ui/badge"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { requiresApproval } from "@/pages/settings/components/permissions/approval-rule-form"
import type { AbilityActionOption, ApprovalRule } from "@/types/serializers"

export function RequiresApprovalBadge({ action, rules }: { action: AbilityActionOption; rules: ApprovalRule[] }) {
  if (!requiresApproval(action, rules)) {
    return null
  }
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Badge variant="outline" className="shrink-0 gap-1">
          <IconShieldCheck className="size-3" />
          approval
        </Badge>
      </TooltipTrigger>
      <TooltipContent side="left">An approval rule holds calls to this ability until someone approves.</TooltipContent>
    </Tooltip>
  )
}
