import { useEffect, useState } from "react"

import type { ApiKey } from "@/types/serializers"
import { abilitiesApiKeyPath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

interface Ability {
  action_key: string
  risk_level: string | null
  reversible: boolean | null
  scopes: Record<string, string[]>[]
  implicit?: boolean
}

interface AbilitiesResponse {
  principal: string
  mode: string
  abilities: Ability[]
}

export function AbilitiesDialog({
  apiKey,
  onDismiss,
}: {
  apiKey: ApiKey | null
  onDismiss: () => void
}) {
  const [response, setResponse] = useState<AbilitiesResponse | null>(null)

  useEffect(() => {
    if (!apiKey) {
      setResponse(null)
      return
    }
    let cancelled = false
    fetch(abilitiesApiKeyPath(apiKey.id), { headers: { Accept: "application/json" } })
      .then((res) => res.json())
      .then((data: AbilitiesResponse) => {
        if (!cancelled) setResponse(data)
      })
    return () => {
      cancelled = true
    }
  }, [apiKey])

  return (
    <Dialog open={apiKey !== null} onOpenChange={(open) => { if (!open) onDismiss() }}>
      <DialogContent className="max-h-[80vh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>Resolved abilities</DialogTitle>
          <DialogDescription>
            What {apiKey?.name} can actually do, as resolved by the gateway
            {response?.mode === "personal" ? " (the human's member-level authority)" : ""}.
          </DialogDescription>
        </DialogHeader>
        {response === null ? (
          <p className="text-muted-foreground py-6 text-center text-sm">Loading…</p>
        ) : response.abilities.length === 0 ? (
          <p className="text-muted-foreground py-6 text-center text-sm">
            This key holds no abilities, so it cannot do anything until granted.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Action</TableHead>
                <TableHead>Risk</TableHead>
                <TableHead>Scope</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {response.abilities.map((ability) => (
                <TableRow key={ability.action_key}>
                  <TableCell>
                    <code className="text-xs">{ability.action_key}</code>
                    {ability.implicit && (
                      <Badge variant="secondary" className="ml-2 text-xs">
                        implicit
                      </Badge>
                    )}
                  </TableCell>
                  <TableCell>
                    <Badge variant={ability.risk_level === "destructive" ? "destructive" : "outline"}>
                      {ability.risk_level ?? "unknown"}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-muted-foreground text-xs">
                    {ability.scopes.every((scope) => Object.keys(scope).length === 0)
                      ? "unrestricted"
                      : JSON.stringify(ability.scopes)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </DialogContent>
    </Dialog>
  )
}
