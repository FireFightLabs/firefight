import { IconGripVertical, IconPlus, IconShieldCheck } from "@tabler/icons-react"

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
import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Textarea } from "@/components/ui/textarea"

import type { Role } from "@/modules/settings/types"
import { RowActions } from "./shared"

const mockRoles: Role[] = [
  {
    id: "1",
    name: "Incident Lead",
    slug: "incident_lead",
    description: "Primary person responsible for driving the incident to resolution",
    position: 1,
    required: true,
  },
  {
    id: "2",
    name: "Communications Lead",
    slug: "communications_lead",
    description: "Responsible for internal and external communications during the incident",
    position: 2,
    required: false,
  },
  {
    id: "3",
    name: "Scribe",
    slug: "scribe",
    description: "Documents the timeline, decisions, and actions taken during the incident",
    position: 3,
    required: false,
  },
  {
    id: "4",
    name: "Subject Matter Expert",
    slug: "subject_matter_expert",
    description: "Technical expert brought in for domain-specific knowledge",
    position: 4,
    required: false,
  },
]

export function RolesTab() {
  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Incident Roles</CardTitle>
            <CardDescription className="mt-1">
              Define the roles that can be assigned to team members during an incident.
            </CardDescription>
          </div>
          <Dialog>
            <DialogTrigger asChild>
              <Button size="sm">
                <IconPlus className="size-4" />
                Add Role
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Add Role</DialogTitle>
                <DialogDescription>
                  Create a new incident role for your workspace.
                </DialogDescription>
              </DialogHeader>
              <div className="flex flex-col gap-4 py-2">
                <div className="flex flex-col gap-2">
                  <Label htmlFor="role-name">Name</Label>
                  <Input id="role-name" placeholder="e.g. Operations Lead" />
                </div>
                <div className="flex flex-col gap-2">
                  <Label htmlFor="role-desc">Description</Label>
                  <Textarea
                    id="role-desc"
                    placeholder="What is this role responsible for?"
                    rows={3}
                  />
                </div>
                <div className="flex items-center justify-between rounded-lg border p-3">
                  <div>
                    <Label htmlFor="role-required" className="text-sm font-medium">Required</Label>
                    <p className="text-xs text-muted-foreground">
                      Must be assigned before an incident can be closed
                    </p>
                  </div>
                  <Switch id="role-required" />
                </div>
              </div>
              <DialogFooter>
                <DialogClose asChild>
                  <Button variant="outline">Cancel</Button>
                </DialogClose>
                <Button>Create Role</Button>
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
              <TableHead>Name</TableHead>
              <TableHead className="hidden md:table-cell">Description</TableHead>
              <TableHead className="w-24 text-center">Required</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {mockRoles.map((role) => (
              <TableRow key={role.id}>
                <TableCell>
                  <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{role.name}</span>
                    {role.slug === "incident_lead" && (
                      <Badge variant="outline" className="text-xs gap-1">
                        <IconShieldCheck className="size-3" />
                        System
                      </Badge>
                    )}
                  </div>
                </TableCell>
                <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                  {role.description}
                </TableCell>
                <TableCell className="text-center">
                  <Switch checked={role.required} />
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
