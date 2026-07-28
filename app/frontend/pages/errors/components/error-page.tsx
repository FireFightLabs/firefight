import { Link } from "@inertiajs/react";

import { Card } from "@/components/card";
import { Button } from "@/components/ui/button";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import { dashboardPath, loginPath } from "@/lib/routes";

// Shared by every error status so a 404 and a 500 differ only in their words.
export function ErrorPage({
  code,
  title,
  description,
  signedIn,
}: {
  code: string;
  title: string;
  description: string;
  signedIn: boolean;
}) {
  return (
    <AuthLayout title={title}>
      <Card variant="glow" className="text-center">
        <CardHeader overline={code} title={title} subtitle={description} />

        <Button asChild className="mx-auto w-full max-w-[320px]">
          <Link href={signedIn ? dashboardPath() : loginPath()}>
            {signedIn ? "Back to dashboard" : "Go to sign in"}
          </Link>
        </Button>
      </Card>
    </AuthLayout>
  );
}
