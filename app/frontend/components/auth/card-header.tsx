import type { ReactNode } from "react";

import { FireFightLogo } from "@/components/fire-fight-logo";

interface CardHeaderProps {
  title: string;
  subtitle?: ReactNode;
  overline?: string;
}

export function CardHeader({ title, subtitle, overline }: CardHeaderProps) {
  return (
    <div className="mb-12 flex flex-col items-center space-y-8 text-center">
      <FireFightLogo className="size-10" />
      <div className="space-y-4">
        {overline ? (
          <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
            {overline}
          </p>
        ) : null}
        <h1 className="text-3xl font-bold tracking-tight text-foreground sm:text-4xl">
          {title}
        </h1>
        {subtitle ? (
          <p className="text-[15px] leading-relaxed text-muted-foreground">
            {subtitle}
          </p>
        ) : null}
      </div>
    </div>
  );
}
