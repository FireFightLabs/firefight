import { router } from "@inertiajs/react"
import { IconDotsVertical } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { gatewayAgentPath, rotateGatewayAgentPath } from "@/lib/routes"
import type { Agent } from "@/types/serializers"

export function AgentRowActions({
  agent,
  onEdit,
  onDelete,
  onManageTokens,
}: {
  agent: Agent
  onEdit: (agent: Agent) => void
  onDelete: (agent: Agent) => void
  onManageTokens: (agent: Agent) => void
}) {
  function edit() {
    onEdit(agent)
  }

  function remove() {
    onDelete(agent)
  }

  function manageTokens() {
    onManageTokens(agent)
  }

  // An overlap, not a swap. The old token keeps working until it is revoked,
  // so the agent stays up while its config is updated.
  function rotate() {
    router.post(rotateGatewayAgentPath(agent.id), {}, { preserveScroll: true })
  }

  function toggle() {
    router.patch(gatewayAgentPath(agent.id), { enabled: !agent.enabled }, { preserveScroll: true })
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="size-8 text-muted-foreground">
          <IconDotsVertical className="size-4" />
          <span className="sr-only">Agent actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-52">
        <DropdownMenuItem onSelect={edit}>Edit</DropdownMenuItem>
        <DropdownMenuItem onSelect={rotate}>Issue a new token</DropdownMenuItem>
        <DropdownMenuItem onSelect={manageTokens}>Tokens ({agent.tokens.length})</DropdownMenuItem>
        <DropdownMenuItem onSelect={toggle}>{agent.enabled ? "Disable" : "Enable"}</DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem variant="destructive" onSelect={remove}>Delete</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
