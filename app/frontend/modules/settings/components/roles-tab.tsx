import * as React from "react"
import { router, useForm } from "@inertiajs/react"
import { IconGripVertical, IconPlus, IconShieldCheck } from "@tabler/icons-react"

import { toast } from "sonner"

import type { IncidentRole } from "@/types/serializers"
import {
  incidentRolesPath,
  incidentRolePath,
  disableIncidentRolePath,
  enableIncidentRolePath,
} from "@/lib/routes"
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
import { RowActions } from "./shared"

interface RolesTabProps {
  roles: IncidentRole[]
}

export function RolesTab({ roles }: RolesTabProps) {
  const [dialogOpen, setDialogOpen] = React.useState(false)
  const form = useForm({ name: "", description: "" })

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    form.post(incidentRolesPath(), {
      onSuccess: () => {
        setDialogOpen(false)
        form.reset()
      },
    })
  }

  function handleToggleEnabled(role: IncidentRole) {
    router.patch(role.enabled ? disableIncidentRolePath(role.id) : enableIncidentRolePath(role.id))
  }

  function handleDelete(role: IncidentRole) {
    if (!role.deletable) {
      toast.error("This role is used by incidents and cannot be deleted. You can disable it instead.")
      return
    }
    router.delete(incidentRolePath(role.id))
  }

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
          <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
            <DialogTrigger asChild>
              <Button size="sm">
                <IconPlus className="size-4" />
                Add Role
              </Button>
            </DialogTrigger>
            <DialogContent>
              <form onSubmit={handleSubmit}>
                <DialogHeader>
                  <DialogTitle>Add Role</DialogTitle>
                  <DialogDescription>
                    Create a new incident role for your workspace.
                  </DialogDescription>
                </DialogHeader>
                <div className="flex flex-col gap-4 py-4">
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="role-name">Name</Label>
                    <Input
                      id="role-name"
                      placeholder="e.g. Operations Lead"
                      value={form.data.name}
                      onChange={(e) => form.setData("name", e.target.value)}
                    />
                    {form.errors.name && (
                      <p className="text-xs text-destructive">{form.errors.name}</p>
                    )}
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="role-desc">Description</Label>
                    <Textarea
                      id="role-desc"
                      placeholder="What is this role responsible for?"
                      rows={3}
                      value={form.data.description}
                      onChange={(e) => form.setData("description", e.target.value)}
                    />
                  </div>
                </div>
                <DialogFooter>
                  <DialogClose asChild>
                    <Button variant="outline" type="button">Cancel</Button>
                  </DialogClose>
                  <Button type="submit" disabled={form.processing}>
                    Create Role
                  </Button>
                </DialogFooter>
              </form>
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
              <TableHead className="w-24 text-center">Enabled</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {roles.map((role) => (
              <TableRow key={role.id} className={!role.enabled ? "opacity-50" : undefined}>
                <TableCell>
                  {!role.system && role.enabled && (
                    <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                  )}
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{role.name}</span>
                    {role.system && (
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
                  <Switch
                    checked={role.enabled}
                    disabled={role.system}
                    onCheckedChange={() => handleToggleEnabled(role)}
                  />
                </TableCell>
                <TableCell>
                  {!role.system && (
                    <RowActions onEdit={() => {}} onDelete={() => handleDelete(role)} />
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}
