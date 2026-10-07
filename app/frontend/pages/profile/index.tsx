import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { SignInMethodsList } from "@/pages/profile/components/sign-in-methods-list"
import type { SignInMethod } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface ProfilePageProps extends SharedProps {
  [key: string]: unknown
  signInMethods: SignInMethod[]
}

function initialsOf(name: string): string {
  return name
    .split(" ")
    .map((part) => part[0])
    .join("")
    .toUpperCase()
}

export default function Profile() {
  const { currentUser, signInMethods } = usePage<ProfilePageProps>().props

  return (
    <AuthenticatedLayout title="Profile">
      <Head title="Profile" />
      <div className="flex max-w-3xl flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        {currentUser ? (
          <Card>
            <CardContent className="flex items-center gap-4">
              <Avatar className="size-12 rounded-lg">
                <AvatarImage src={currentUser.avatarUrl} alt={currentUser.name} />
                <AvatarFallback className="rounded-lg bg-avatar text-avatar-foreground">
                  {initialsOf(currentUser.name)}
                </AvatarFallback>
              </Avatar>
              <div className="min-w-0">
                <p className="truncate font-medium text-fg-primary">{currentUser.name}</p>
                <p className="truncate text-sm text-fg-muted">{currentUser.email}</p>
              </div>
            </CardContent>
          </Card>
        ) : null}

        <Card>
          <CardHeader>
            <CardTitle>Sign-in methods</CardTitle>
            <CardDescription className="mt-1">
              The ways you can sign in to Firefight. We email you whenever a new one is added.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <SignInMethodsList methods={signInMethods} />
          </CardContent>
        </Card>
      </div>
    </AuthenticatedLayout>
  )
}
