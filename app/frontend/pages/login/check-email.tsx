import { Link, usePage } from "@inertiajs/react";

import { Button } from "@/components/ui/button";
import { loginPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import type { SharedProps } from "@/types";

interface CheckEmailPageProps extends SharedProps {
  [key: string]: unknown;
  email: string;
  minutes: number;
}

export default function CheckEmail() {
  const { email, minutes } = usePage<CheckEmailPageProps>().props;

  return (
    <AuthLayout title="Check your email" containerClassName="max-w-[420px]">
      <div className="text-center">
        <CardHeader
          title="Check your email"
          subtitle={
            <>
              We sent a sign-in link to{" "}
              <span className="font-medium text-fg-primary [overflow-wrap:anywhere]">{email}</span>. It works once,
              for the next {minutes} minutes.
            </>
          }
        />
        <p className="text-sm leading-relaxed text-fg-muted">
          Nothing there? Look in your spam folder, or ask for a new link.
        </p>
        <Button asChild variant="outline" className="mt-6 h-11 w-full max-w-[320px] cursor-pointer font-medium">
          <Link href={loginPath()}>Use a different email</Link>
        </Button>
      </div>
    </AuthLayout>
  );
}
