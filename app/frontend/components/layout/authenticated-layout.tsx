import type { CSSProperties, ReactNode } from "react";
import { usePage } from "@inertiajs/react";
import { IconPlugConnectedX } from "@tabler/icons-react";

import { FlashToaster } from "@/components/flash-toaster";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { onboardingReinstallPath } from "@/lib/routes";
import { AppSidebar } from "@/components/navigation/app-sidebar";
import { SiteHeader } from "@/components/navigation/site-header";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";

interface AuthenticatedLayoutProps {
  children: ReactNode;
  title?: string;
}

// Slack has told Firefight the install is gone. Everything already recorded
// stays readable, so the page keeps working and asks an admin to reconnect
// rather than locking anyone out.
function DisconnectedBanner() {
  const { currentWorkspace, currentUserIsAdmin } = usePage().props;

  if (!currentWorkspace?.disconnected) {
    return null;
  }

  return (
    <Alert
      variant="destructive"
      className="mx-6 mt-6 w-auto flex items-center justify-between gap-4"
    >
      <div className="flex items-start gap-3">
        <IconPlugConnectedX className="mt-0.5 size-5 shrink-0" />
        <div>
          <AlertTitle>Slack is disconnected</AlertTitle>
          <AlertDescription>
            Firefight can no longer reach {currentWorkspace.name} in Slack.
            Incidents, settings and history are still here, but nothing will
            post to Slack until the app is reinstalled.
          </AlertDescription>
        </div>
      </div>
      {currentUserIsAdmin ? (
        <Button asChild variant="outline" size="sm" className="shrink-0">
          <a href={onboardingReinstallPath()}>Reconnect Slack</a>
        </Button>
      ) : (
        <span className="text-xs shrink-0">
          Ask a workspace admin to reconnect it.
        </span>
      )}
    </Alert>
  );
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
          <DisconnectedBanner />
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
  );
}
