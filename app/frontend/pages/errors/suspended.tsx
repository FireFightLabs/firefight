import { Link } from "@inertiajs/react";

import { Button } from "@/components/ui/button";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import { logoutPath } from "@/lib/routes";

export default function Suspended({ message }: { message: string }) {
  return (
    <AuthLayout title="Workspace suspended" variant="centered">
      <div className="text-center">
        <CardHeader title="Workspace suspended" subtitle={message} />

        <Button asChild variant="outline" className="mx-auto w-full max-w-[320px]">
          <Link href={logoutPath()} method="delete" as="button">
            Log out
          </Link>
        </Button>
      </div>
    </AuthLayout>
  );
}
