import type { CSSProperties, ReactNode } from "react"

import { FlashToaster } from "@/components/flash-toaster"
import { AppSidebar } from "@/components/navigation/app-sidebar"
import { SiteHeader } from "@/components/navigation/site-header"
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar"
import { Toaster } from "@/components/ui/sonner"
import { TooltipProvider } from "@/components/ui/tooltip"

interface AuthenticatedLayoutProps {
  children: ReactNode
  title?: string
}

export function AuthenticatedLayout({
  children,
  title = "Dashboard",
}: AuthenticatedLayoutProps) {
  return (
    <TooltipProvider>
      <SidebarProvider
        style={
          {
            "--sidebar-width": "calc(var(--spacing) * 72)",
            "--header-height": "calc(var(--spacing) * 16)",
          } as CSSProperties
        }
      >
        <AppSidebar />
        <SidebarInset>
          <SiteHeader title={title} />
          <div className="flex flex-1 flex-col">
            <div className="@container/main flex flex-1 flex-col gap-2 pt-6">
              {children}
            </div>
          </div>
        </SidebarInset>
        <Toaster />
        <FlashToaster />
      </SidebarProvider>
    </TooltipProvider>
  )
}
