import { ErrorPage } from "@/pages/errors/components/error-page";

export default function Unprocessable({ signedIn }: { signedIn: boolean }) {
  return (
    <ErrorPage
      code="422"
      title="That change could not be applied"
      description="The request was rejected before anything was saved. Go back and try again."
      signedIn={signedIn}
    />
  );
}
