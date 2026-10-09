import { useForm } from "@inertiajs/react";
import type { HttpResponse } from "@inertiajs/core";
import type { ChangeEvent, FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { emailSignInPath } from "@/lib/routes";
import { TOO_MANY_STATUS } from "@/lib/http";

const TOO_MANY_MESSAGE = "Too many sign-in links were asked for. Wait a little, then try again.";

export function EmailSignInForm() {
  const form = useForm({ email: "" });

  function changeEmail(event: ChangeEvent<HTMLInputElement>) {
    form.setData("email", event.target.value);
  }

  // A throttled request answers with a plain page, which would otherwise open over the sign-in form.
  function handleHttpException(response: HttpResponse) {
    if (response.status !== TOO_MANY_STATUS) {
      return;
    }
    form.setError("email", [TOO_MANY_MESSAGE]);
    return false;
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    form.post(emailSignInPath(), { onHttpException: handleHttpException });
  }

  return (
    <form className="space-y-3 text-left" onSubmit={submit} noValidate>
      <div className="space-y-2">
        <Label htmlFor="sign-in-email">Email</Label>
        <Input
          id="sign-in-email"
          name="email"
          type="email"
          autoComplete="email"
          value={form.data.email}
          onChange={changeEmail}
          placeholder="you@company.com"
          aria-invalid={form.errors.email ? true : undefined}
        />
        {form.errors.email ? (
          <p className="text-sm text-destructive">{form.errors.email.join(" ")}</p>
        ) : null}
      </div>
      <Button
        type="submit"
        variant="outline"
        className="h-11 w-full cursor-pointer font-medium"
        disabled={form.processing}
      >
        Email me a sign-in link
      </Button>
    </form>
  );
}
