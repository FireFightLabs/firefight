import type { ReactNode } from "react";

import { FireFightLogo } from "@/components/fire-fight-logo";

interface CardHeaderProps {
  title: string;
  subtitle?: ReactNode;
  overline?: string;
}

export function CardHeader({ title, subtitle, overline }: CardHeaderProps) {
  return (
    <div className="mb-8 flex flex-col items-center space-y-4 text-center">
      <FireFightLogo />
      <div className="space-y-2">
        {overline ? (
          <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
            {overline}
          </p>
        ) : null}
        <h1 className="text-2xl font-semibold tracking-tight text-foreground">
          {title}
        </h1>
        {subtitle ? (
          <p className="text-sm leading-relaxed text-muted-foreground">
            {subtitle}
          </p>
        ) : null}
      </div>
    </div>
  );
}
