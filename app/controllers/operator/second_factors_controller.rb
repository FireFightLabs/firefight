module Operator
  # Authenticator setup on the first visit, and the code check on later visits.
  class SecondFactorsController < BaseController
    skip_before_action :require_second_factor!
    before_action :require_setup, only: %i[verify check]

    def setup
      credential = Credential.start_for!(current_user)
      return redirect_to operator_verify_path if credential.confirmed?

      render inertia: "operator/setup", props: {
        qr: credential.qr_modules, secret: credential.display_secret, account: current_user.email
      }
    end

    # Renders the recovery codes instead of redirecting, so they never appear in a URL, flash message or log.
    def confirm
      credential = Credential.start_for!(current_user)
      return redirect_to operator_verify_path if credential.confirmed?

      codes = credential.confirm!(params[:code])
      return redirect_to operator_setup_path, inertia: { errors: { code: refusal(credential) } } unless codes

      mark_verified!
      render inertia: "operator/recovery-codes", props: { codes: codes }
    end

    def verify
      return redirect_to operator_root_path if operator_verified?

      render inertia: "operator/verify", props: { recoveryCodesLeft: credential.recovery_codes_left }
    end

    def check
      return redirect_to operator_verify_path, inertia: { errors: { code: refusal(credential) } } unless credential.verify!(params[:code])

      mark_verified!
      open_console(session.delete(:operator_return_to).presence || operator_root_path)
    end

    private

    def credential = @credential ||= Credential.for(current_user)

    # Flightdeck pages are not Inertia pages, so after a correct code the browser loads the next page in full.
    def open_console(path)
      request.inertia? ? inertia_location(path) : redirect_to(path)
    end

    def require_setup
      redirect_to operator_setup_path unless credential&.confirmed?
    end

    def refusal(credential)
      credential.reload.locked? ? Credential::LOCKED_MESSAGE : Credential::WRONG_MESSAGE
    end
  end
end
