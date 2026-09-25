import { Link, usePage } from "@inertiajs/react"

import { Card } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { operatorHalonChatPath, operatorHalonChatsPath } from "@/lib/routes"
import { FilterBar } from "@/pages/operator/components/filter-bar"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Pager } from "@/pages/operator/components/pager"
import { dollars } from "@/pages/operator/lib/format"
import type { FilterProps, OperatorPageProps } from "@/pages/operator/types"
import type { OperatorHalonChat } from "@/types/serializers"

interface ChatsProps extends OperatorPageProps, FilterProps {
  chats: OperatorHalonChat[]
  page: number
  more: boolean
}

export default function OperatorHalonChats() {
  const props = usePage<ChatsProps>().props
  const { chats, page, more, filter } = props

  function pageHref(target: number) {
    return operatorHalonChatsPath({ window: filter.window, workspace: filter.workspace ?? undefined, page: target })
  }

  return (
    <OperatorLayout title="Chats">
      <PageHeading
        title="Chats"
        lead="Every chat with Halon active in the window, newest first, from the dashboard, the chat platform and other agents. Open one to see its turns on the trace."
      />
      <FilterBar filter={filter} windows={props.windows} workspaces={props.workspaces} />
      <Card className="gap-0 overflow-hidden py-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Chat</TableHead>
              <TableHead>Workspace</TableHead>
              <TableHead>Kind</TableHead>
              <TableHead className="text-right">Turns</TableHead>
              <TableHead className="text-right">Spent</TableHead>
              <TableHead>Last active</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {chats.map((chat) => (
              <TableRow key={chat.id}>
                <TableCell className="max-w-md">
                  <Link href={operatorHalonChatPath(chat.id)} className="flex min-w-0 flex-col hover:underline">
                    <span className="truncate">{chat.title}</span>
                    {chat.incidentLabel && <span className="text-muted-foreground font-mono text-xs">{chat.incidentLabel}</span>}
                  </Link>
                </TableCell>
                <TableCell className="text-muted-foreground">{chat.workspaceName}</TableCell>
                <TableCell className="text-muted-foreground">{chat.kind}</TableCell>
                <TableCell className="text-right font-mono">{chat.turns}</TableCell>
                <TableCell className="text-right font-mono">{dollars(chat.spentMicros)}</TableCell>
                <TableCell className="text-muted-foreground">{formatDateTime(chat.updatedAt)}</TableCell>
              </TableRow>
            ))}
            {chats.length === 0 && (
              <TableRow>
                <TableCell colSpan={6} className="text-muted-foreground py-10 text-center">No chats in this window.</TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
        <Pager page={page} more={more} hrefFor={pageHref} />
      </Card>
    </OperatorLayout>
  )
}
