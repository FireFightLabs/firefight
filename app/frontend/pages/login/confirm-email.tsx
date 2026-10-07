import { Link, useForm, usePage } from "@inertiajs/react";
import type { FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { consumeEmailSignInPath, loginPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import type { SharedProps } from "@/types";

interface ConfirmEmailPageProps extends SharedProps {
  [key: string]: unknown;
  token: string;
  usable: boolean;
  minutes: number;
}

export default function ConfirmEmail() {
  const { token, usable, minutes } = usePage<ConfirmEmailPageProps>().props;
  const form = useForm({ token });

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    form.post(consumeEmailSignInPath());
  }

  if (!usable) {
    return (
      <AuthLayout title="Link expired" containerClassName="max-w-[420px]">
        <div className="text-center">
          <CardHeader
            title="This link has expired"
            subtitle={`A sign-in link works once, for ${minutes} minutes. Ask for a new one.`}
          />
          <Button asChild className="h-11 w-full max-w-[320px] cursor-pointer font-medium">
            <Link href={loginPath()}>Back to sign in</Link>
          </Button>
        </div>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout title="Sign in to Firefight" containerClassName="max-w-[420px]">
      <div className="text-center">
        <CardHeader title="Finish signing in" subtitle="Click below to sign in to Firefight." />
        <form onSubmit={submit} className="mx-auto max-w-[320px]">
          <Button type="submit" className="h-11 w-full cursor-pointer font-medium" disabled={form.processing}>
            Sign in
          </Button>
        </form>
      </div>
    </AuthLayout>
  );
}
