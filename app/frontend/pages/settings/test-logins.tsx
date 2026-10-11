import { useState } from "react"
import { Head, router, usePage } from "@inertiajs/react"
import { IconLogin2 } from "@tabler/icons-react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { RowActions } from "@/components/row-actions"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { TestLoginDialog } from "@/pages/settings/components/test-logins/test-login-dialog"
import { testLoginPath } from "@/lib/routes"
import type { TestLogin } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface TestLoginsPageProps extends SharedProps {
  testLogins: TestLogin[]
}

function TestLoginRow({
  login,
  onEdit,
  onDelete,
}: {
  login: TestLogin
  onEdit: (login: TestLogin) => void
  onDelete: (login: TestLogin) => void
}) {
  return (
    <TableRow>
      <TableCell>
        <span className="font-medium text-foreground">{login.name}</span>
        <span className="block break-all text-xs text-muted-foreground">{login.siteUrl}</span>
      </TableCell>
      <TableCell className="hidden md:table-cell break-all text-sm text-muted-foreground">
        {login.loginUrl ?? "-"}
      </TableCell>
      <TableCell className="text-sm break-all">{login.username}</TableCell>
      <TableCell className="hidden lg:table-cell text-sm text-muted-foreground">{login.passwordHint}</TableCell>
      <TableCell>
        <RowActions onEdit={() => onEdit(login)} onDelete={() => onDelete(login)} />
      </TableCell>
    </TableRow>
  )
}

export default function TestLoginsPage() {
  const { testLogins } = usePage<TestLoginsPageProps>().props
  const [editing, setEditing] = useState<TestLogin | null>(null)
  const [deleting, setDeleting] = useState<TestLogin | null>(null)

  function closeEdit() {
    setEditing(null)
  }

  function cancelDelete() {
    setDeleting(null)
  }

  function confirmDelete() {
    if (!deleting) {
      return
    }
    router.delete(testLoginPath(deleting.id), { preserveScroll: true })
    setDeleting(null)
  }

  return (
    <AuthenticatedLayout title="Test logins">
      <Head title="Test logins" />

      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <Card>
          <CardHeader>
            <div className="flex items-start justify-between gap-4">
              <div>
                <CardTitle>Test logins</CardTitle>
                <CardDescription className="mt-1">
                  A test account per site, which Halon&apos;s browser signs in with when it checks a page there.
                  Firefight signs in itself, so the password never reaches Halon, a chat or the activity log.
                </CardDescription>
              </div>
              <TestLoginDialog />
            </div>
          </CardHeader>

          {testLogins.length === 0 ? (
            <CardContent>
              <div className="flex flex-col items-center gap-2 py-10 text-center">
                <IconLogin2 className="size-7 text-fg-disabled" aria-hidden />
                <p className="max-w-md text-sm text-muted-foreground">
                  No test logins yet. Save one for a site behind a login, and Halon can check the pages there the way
                  a signed in customer sees them.
                </p>
              </div>
            </CardContent>
          ) : (
            <CardContent className="p-0">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead>Site</TableHead>
                    <TableHead className="hidden md:table-cell">Login page</TableHead>
                    <TableHead>Username</TableHead>
                    <TableHead className="hidden lg:table-cell">Password</TableHead>
                    <TableHead className="w-12" />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {testLogins.map((login) => (
                    <TestLoginRow key={login.id} login={login} onEdit={setEditing} onDelete={setDeleting} />
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          )}
        </Card>
      </div>

      {editing && <TestLoginDialog login={editing} open onOpenChange={closeEdit} />}

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete the test login for ${deleting?.name ?? "this site"}?`}
        description={`The username and password saved for ${deleting?.siteUrl ?? "this site"} are deleted, and Halon's browser no longer signs in there. Checks of its public pages still work.`}
        onConfirm={confirmDelete}
        onCancel={cancelDelete}
      />
    </AuthenticatedLayout>
  )
}
