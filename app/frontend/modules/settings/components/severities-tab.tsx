import { IconGripVertical, IconPlus } from "@tabler/icons-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Textarea } from "@/components/ui/textarea"

import type { Severity } from "@/modules/settings/types"
import { ColorDot, RowActions } from "./shared"

const mockSeverities: Severity[] = [
  { id: "1", name: "Critical", slug: "critical", description: "Complete service outage or data loss affecting all users", color: "#DC143C", rank: 5, position: 1, isDefault: false },
  { id: "2", name: "Major", slug: "major", description: "Significant impact with degraded functionality for many users", color: "#FF6B35", rank: 3, position: 2, isDefault: false },
  { id: "3", name: "Minor", slug: "minor", description: "Limited impact, workaround available", color: "#FFA500", rank: 1, position: 3, isDefault: true },
]

export function SeveritiesTab() {
  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Severities</CardTitle>
            <CardDescription className="mt-1">
              Define severity levels for classifying incident impact. Higher rank means more severe.
            </CardDescription>
          </div>
          <Dialog>
            <DialogTrigger asChild>
              <Button size="sm">
                <IconPlus className="size-4" />
                Add Severity
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Add Severity</DialogTitle>
                <DialogDescription>
                  Create a new severity level for your workspace.
                </DialogDescription>
              </DialogHeader>
              <div className="flex flex-col gap-4 py-2">
                <div className="flex flex-col gap-2">
                  <Label htmlFor="sev-name">Name</Label>
                  <Input id="sev-name" placeholder="e.g. Moderate" />
                </div>
                <div className="flex flex-col gap-2">
                  <Label htmlFor="sev-desc">Description</Label>
                  <Textarea
                    id="sev-desc"
                    placeholder="When should this severity be assigned?"
                    rows={2}
                  />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="sev-rank">Rank</Label>
                    <Input
                      id="sev-rank"
                      type="number"
                      min={1}
                      placeholder="1"
                    />
                    <p className="text-xs text-muted-foreground">
                      Higher rank = more severe
                    </p>
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="sev-color">Color</Label>
                    <div className="flex items-center gap-2">
                      <Input
                        id="sev-color"
                        type="color"
                        defaultValue="#FF6B35"
                        className="h-9 w-12 cursor-pointer p-1"
                      />
                      <Input
                        defaultValue="#FF6B35"
                        className="flex-1 font-mono text-sm"
                        placeholder="#FF6B35"
                      />
                    </div>
                  </div>
                </div>
              </div>
              <DialogFooter>
                <DialogClose asChild>
                  <Button variant="outline">Cancel</Button>
                </DialogClose>
                <Button>Create Severity</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </CardHeader>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="w-8" />
              <TableHead>Severity</TableHead>
              <TableHead className="hidden md:table-cell">Description</TableHead>
              <TableHead className="w-20 text-center">Rank</TableHead>
              <TableHead className="w-24 text-center">Default</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {mockSeverities.map((severity) => (
              <TableRow key={severity.id}>
                <TableCell>
                  <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2.5">
                    <ColorDot color={severity.color} />
                    <span className="font-medium">{severity.name}</span>
                  </div>
                </TableCell>
                <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                  {severity.description}
                </TableCell>
                <TableCell className="text-center">
                  <Badge variant="outline" className="font-mono tabular-nums">
                    {severity.rank}
                  </Badge>
                </TableCell>
                <TableCell className="text-center">
                  {severity.isDefault && (
                    <Badge variant="secondary" className="text-xs">
                      Default
                    </Badge>
                  )}
                </TableCell>
                <TableCell>
                  <RowActions onEdit={() => {}} onDelete={() => {}} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}
