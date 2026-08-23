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
          <aside className="relative hidden w-1/2 overflow-hidden border-r border-border/60 bg-[linear-gradient(150deg,#122338,#0c1626_55%,#0a1220)] lg:flex lg:flex-col lg:justify-end lg:p-10">
            <div aria-hidden="true" className="pointer-events-none absolute inset-0">
              <div className="absolute left-1/2 top-[-30%] h-[90%] w-[130%] -translate-x-1/2 bg-[radial-gradient(ellipse_50%_60%_at_50%_0%,rgba(115,211,238,0.2),transparent_70%)]" />
              <div className="absolute right-[-10%] top-[-40%] h-[130%] w-[60%] rotate-[26deg] bg-[linear-gradient(190deg,rgba(148,197,255,0.18),rgba(115,211,238,0.07)_45%,transparent_70%)] blur-3xl" />
              <div className="absolute bottom-[-30%] left-[-15%] h-[70%] w-[70%] bg-[radial-gradient(ellipse_at_center,rgba(115,211,238,0.08),transparent_65%)] blur-2xl" />
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
            className={cn(
              "pointer-events-none absolute inset-0",
              variant === "split" && "lg:hidden",
            )}
          >
            <div className="absolute left-1/2 top-[-30%] h-[90%] w-[130%] -translate-x-1/2 bg-[radial-gradient(ellipse_50%_60%_at_50%_0%,rgba(115,211,238,0.14),transparent_70%)]" />
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
