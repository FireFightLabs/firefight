import { Head } from "@inertiajs/react";
import type { ReactNode } from "react";

import { cn } from "@/lib/utils";

interface AuthLayoutProps {
  title: string;
  containerClassName?: string;
  children: ReactNode;
}

export function AuthLayout({
  title,
  containerClassName,
  children,
}: AuthLayoutProps) {
  return (
    <>
      <Head title={title} />
      <div className="relative flex min-h-svh flex-col bg-background text-foreground">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(115,211,238,0.03)_1px,transparent_1px),linear-gradient(to_bottom,rgba(115,211,238,0.03)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
        />

        <main className="relative flex flex-1 items-center justify-center px-4 py-12 sm:px-6">
          <div className={cn("w-full max-w-[480px]", containerClassName)}>
            {children}
          </div>
        </main>
      </div>
    </>
  );
}
