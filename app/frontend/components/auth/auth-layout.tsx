import { Head } from "@inertiajs/react";
import type { ReactNode } from "react";

import { FlashToaster } from "@/components/flash-toaster";
import { Toaster } from "@/components/ui/sonner";
import { TOAST_OPTIONS } from "@/lib/toast-options";
import { cn } from "@/lib/utils";

interface AuthLayoutProps {
  title: string;
  containerClassName?: string;
  // split shows the brand panel on large screens, centered never does
  variant?: "split" | "centered";
  children: ReactNode;
}

export function AuthLayout({
  title,
  containerClassName,
  variant = "split",
  children,
}: AuthLayoutProps) {
  return (
    <>
      <Head title={title} />
      <div className="flex min-h-svh bg-background text-fg-primary">
        {variant === "split" ? (
          <aside className="relative hidden w-1/2 overflow-hidden border-r border-border bg-surface-card lg:flex lg:flex-col lg:justify-end lg:p-10">
            <div className="relative space-y-4">
              <h2 className="max-w-md text-3xl font-semibold leading-tight tracking-tight text-fg-headline">
                Incident management where your team{" "}
                <span className="text-fg-secondary">already works.</span>
              </h2>
              <p className="max-w-sm text-[15px] leading-relaxed text-fg-body">
                Declare, coordinate and resolve incidents without leaving
                Slack. The dashboard keeps the full picture.
              </p>
            </div>
          </aside>
        ) : null}

        <main className="relative flex flex-1 items-center justify-center overflow-hidden px-4 py-12 sm:px-6">
          <div className={cn("relative w-full max-w-[480px]", containerClassName)}>
            {children}
          </div>
        </main>

        <Toaster toastOptions={TOAST_OPTIONS} />
        <FlashToaster />
      </div>
    </>
  );
}
