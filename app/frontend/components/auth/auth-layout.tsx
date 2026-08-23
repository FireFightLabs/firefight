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
        <main className="relative flex flex-1 items-center justify-center px-4 py-12 sm:px-6">
          <div className={cn("w-full max-w-[480px]", containerClassName)}>
            {children}
          </div>
        </main>
      </div>
    </>
  );
}
