import { Link, useForm, usePage } from "@inertiajs/react";
import type { FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { acceptInvitationPath, loginPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import type { SharedProps } from "@/types";

interface InvitationPageProps extends SharedProps {
  [key: string]: unknown;
  token: string;
  usable: boolean;
  workspaceName: string | null;
  inviterName: string | null;
  email: string | null;
  days: number;
}

// Opening the link only shows this, since mail scanners fetch every link. The button signs the person in.
export default function Invitation() {
  const { token, usable, workspaceName, inviterName, email, days } = usePage<InvitationPageProps>().props;
  const form = useForm({ token });

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    form.post(acceptInvitationPath());
  }

  if (!usable) {
    return (
      <AuthLayout title="Invitation expired" containerClassName="max-w-[420px]">
        <div className="text-center">
          <CardHeader
            title="This invitation has expired"
            subtitle={`An invitation works once, for ${days} days, and an admin can take it back. Ask whoever invited you to send it again.`}
          />
          <Button asChild className="h-11 w-full max-w-[320px] cursor-pointer font-medium">
            <Link href={loginPath()}>Go to sign in</Link>
          </Button>
        </div>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout title={`Join ${workspaceName}`} containerClassName="max-w-[420px]">
      <div className="text-center">
        <CardHeader
          title={`Join ${workspaceName}`}
          subtitle={
            <>
              {inviterName ? `${inviterName} invited you` : "You are invited"} to {workspaceName} on Firefight. You
              will be signed in as <span className="font-medium text-fg-primary">{email}</span>.
            </>
          }
        />
        <form onSubmit={submit} className="mx-auto max-w-[320px]">
          <Button type="submit" className="h-11 w-full cursor-pointer font-medium" disabled={form.processing}>
            Join {workspaceName}
          </Button>
        </form>
      </div>
    </AuthLayout>
  );
}
