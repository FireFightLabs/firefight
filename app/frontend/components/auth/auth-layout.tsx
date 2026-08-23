import { Head } from "@inertiajs/react";
import type { ReactNode } from "react";

import { FlashToaster } from "@/components/flash-toaster";
import { Toaster } from "@/components/ui/sonner";
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
      <div className="flex min-h-svh bg-background text-foreground">
        {variant === "split" ? (
          <aside className="auth-aside">
            <div aria-hidden="true" className="pointer-events-none absolute inset-0">
              <div className="auth-beam-top" />
              <div className="auth-beam-diagonal" />
              <div className="auth-beam-low" />
            </div>

            <div className="relative space-y-4">
              <h2 className="max-w-md text-3xl font-bold leading-tight tracking-tight">
                Incident management where your team{" "}
                <span className="text-primary">already works.</span>
              </h2>
              <p className="max-w-sm text-[15px] leading-relaxed text-muted-foreground">
                Declare, coordinate and resolve incidents without leaving
                Slack. The dashboard keeps the full picture.
              </p>
            </div>
          </aside>
        ) : null}

        <main className="relative flex flex-1 items-center justify-center overflow-hidden px-4 py-12 sm:px-6">
          <div
            aria-hidden="true"
            className={variant === "split" ? "auth-mobile-glow" : "auth-centered-glow"}
          >
            <div />
          </div>

          <div className={cn("relative w-full max-w-[480px]", containerClassName)}>
            {children}
          </div>
        </main>

        <Toaster />
        <FlashToaster />
      </div>
    </>
  );
}
