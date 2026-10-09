import { type CSSProperties, type ReactNode, useCallback, useEffect, useState } from "react";

import { FlashToaster } from "@/components/flash-toaster";
import { CloudBanner } from "@/components/layout/cloud-banner";
import { ConnectSlackBanner } from "@/components/layout/connect-slack-banner";
import { DisconnectedBanner } from "@/components/layout/disconnected-banner";
import { AppSidebar } from "@/components/navigation/app-sidebar";
import { SearchPalette } from "@/components/navigation/search-palette";
import { SiteHeader } from "@/components/navigation/site-header";
import { useSearchShortcut } from "@/hooks/use-search-shortcut";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { Toaster } from "@/components/ui/sonner";
import { TOAST_OPTIONS } from "@/lib/toast-options";
import { TooltipProvider } from "@/components/ui/tooltip";

interface AuthenticatedLayoutProps {
  children: ReactNode;
  title?: string;
  actions?: ReactNode;
  sidebarCollapsed?: boolean;
  // A page that answers Cmd or Ctrl K with a search of its own keeps it, and the search stays a click away in the header.
  ownsSearchShortcut?: boolean;
}

// Module scope because every page mounts its own layout, null after a full load.
let sidebarWasOpen: boolean | null = null;

// Renders open and collapses a frame later, so the nav slides shut instead of vanishing.
function useSidebarOpen(collapsed: boolean) {
  const [open, setOpen] = useState(collapsed ? sidebarWasOpen === true : true);

  useEffect(() => {
    if (!collapsed) {
      return;
    }

    const frame = requestAnimationFrame(() => setOpen(false));
    return () => cancelAnimationFrame(frame);
  }, [collapsed]);

  useEffect(() => {
    sidebarWasOpen = open;
  }, [open]);

  return [open, setOpen] as const;
}

export function AuthenticatedLayout({
  children,
  title = "Dashboard",
  actions,
  sidebarCollapsed = false,
  ownsSearchShortcut = false,
}: AuthenticatedLayoutProps) {
  const [sidebarOpen, setSidebarOpen] = useSidebarOpen(sidebarCollapsed);
  const [searching, setSearching] = useState(false);
  const openSearch = useCallback(() => setSearching(true), []);
  useSearchShortcut(openSearch, !ownsSearchShortcut);

  return (
    <TooltipProvider>
      <SidebarProvider
        open={sidebarOpen}
        onOpenChange={setSidebarOpen}
        style={
          {
            "--sidebar-width": "calc(var(--spacing) * 72)",
            "--header-height": "calc(var(--spacing) * 16)",
          } as CSSProperties
        }
      >
        <AppSidebar />
        <SidebarInset>
          <SiteHeader title={title} actions={actions} onSearch={openSearch} searchShortcut={!ownsSearchShortcut} />
          <DisconnectedBanner />
          <CloudBanner />
          <ConnectSlackBanner />
          <div className="flex flex-1 flex-col">
            <div className="@container/main flex flex-1 flex-col gap-2 pt-6">
              {children}
            </div>
          </div>
        </SidebarInset>
        <SearchPalette open={searching} onOpenChange={setSearching} />
        <Toaster toastOptions={TOAST_OPTIONS} />
        <FlashToaster />
      </SidebarProvider>
    </TooltipProvider>
  );
}
