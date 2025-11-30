import { Head, usePage } from '@inertiajs/react'
import { AuthenticatedLayout } from '@/components/layout/authenticated-layout'
import { SharedProps } from '@/types'

export default function Dashboard() {
  const { currentUser, currentWorkspace } = usePage<SharedProps>().props

  return (
    <AuthenticatedLayout>
      <Head title="Dashboard" />
      <div className="container mx-auto p-6">
        <div className="space-y-4">
          <h1 className="text-3xl font-bold">
            Welcome, {currentUser?.name}!
          </h1>
          <p className="text-muted-foreground">
            You're connected to {currentWorkspace?.name}
          </p>
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
