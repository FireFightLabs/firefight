import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import { operatorVerifyPath } from "@/lib/routes";
import { CodeForm } from "@/pages/operator/components/code-form";

export default function OperatorVerify({ recoveryCodesLeft }: { recoveryCodesLeft: number }) {
  return (
    <AuthLayout title="Enter your code" variant="centered">
      <CardHeader
        overline="Operator console"
        title="Enter your code"
        subtitle="Open your authenticator app and enter the six digits it shows for Firefight Operator."
      />
      <CodeForm
        action={operatorVerifyPath()}
        label="Code"
        submitLabel="Open the console"
        hint={`Lost your phone? Enter a recovery code instead. You have ${recoveryCodesLeft} left.`}
      />
    </AuthLayout>
  );
}
