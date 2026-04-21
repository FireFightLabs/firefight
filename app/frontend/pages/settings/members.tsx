import { Head, usePage } from "@inertiajs/react";

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { WorkspaceMembership } from "@/types/serializers";
import type { SharedProps } from "@/types";

interface MembersPageProps extends SharedProps {
  [key: string]: unknown;
  members: WorkspaceMembership[];
}

export default function Members() {
  const { members } = usePage<MembersPageProps>().props;

  return (
    <AuthenticatedLayout title="Members">
      <Head title="Members" />
      <div className="flex flex-col gap-8 px-4 py-4 md:py-6 lg:px-6">
        <section className="space-y-4">
          <div className="space-y-1">
            <h2 className="text-lg font-semibold tracking-tight text-foreground">
              Members
            </h2>
            <p className="text-sm text-muted-foreground">
              Anyone in your Slack workspace who uses Firefight is added here automatically.
            </p>
          </div>

          <MembersTable members={members} />
        </section>
      </div>
    </AuthenticatedLayout>
  );
}

function MembersTable({ members }: { members: WorkspaceMembership[] }) {
  return (
    <div className="rounded-lg border border-border bg-card">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Person</TableHead>
            <TableHead>Role</TableHead>
            <TableHead>Joined</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {members.map((m) => (
            <TableRow key={m.id}>
              <TableCell>
                <div className="flex items-center gap-3">
                  <Avatar className="size-8">
                    {m.avatarUrl ? (
                      <AvatarImage src={m.avatarUrl} alt={m.name} />
                    ) : null}
                    <AvatarFallback>{initials(m.name)}</AvatarFallback>
                  </Avatar>
                  <div className="leading-tight">
                    <div className="font-medium text-foreground">{m.name}</div>
                    <div className="text-xs text-muted-foreground">
                      {m.email}
                    </div>
                  </div>
                </div>
              </TableCell>
              <TableCell>
                <Badge variant="secondary" className="font-normal">
                  {m.role}
                </Badge>
              </TableCell>
              <TableCell className="text-sm text-muted-foreground tabular-nums">
                {formatDate(m.joinedAt)}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

function initials(name: string) {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join("");
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}
