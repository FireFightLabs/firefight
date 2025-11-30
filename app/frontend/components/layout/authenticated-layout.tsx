import { ReactNode } from 'react'
import { UserNav } from './user-nav'

interface AuthenticatedLayoutProps {
  children: ReactNode
}

export function AuthenticatedLayout({ children }: AuthenticatedLayoutProps) {
  return (
    <div className="min-h-screen bg-background">
      <header className="border-b">
        <div className="container mx-auto flex h-16 items-center justify-between px-4">
          <div className="flex items-center gap-6">
            <h2 className="text-xl font-bold">Firefight</h2>
          </div>
          <UserNav />
        </div>
      </header>
      <main>{children}</main>
    </div>
  )
}
