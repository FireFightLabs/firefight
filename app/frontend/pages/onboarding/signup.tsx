import { Link } from "@inertiajs/react";

import { Button } from "@/components/ui/button";
import { loginPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";

export default function Signup() {
  return (
    <AuthLayout title="Signup is coming soon" containerClassName="max-w-[420px]">
      <div className="text-center">
        <CardHeader
          title="Signup is coming soon"
          subtitle="No Firefight workspace has this account in it, and you can't create one this way yet. If your team already uses Firefight, sign in with Slack."
        />
        <Button asChild className="h-11 w-full max-w-[320px] cursor-pointer font-medium">
          <Link href={loginPath()}>Back to sign in</Link>
        </Button>
      </div>
    </AuthLayout>
  );
}
