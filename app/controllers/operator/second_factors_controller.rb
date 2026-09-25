module Operator
  # Setting up an authenticator once, then entering its code each time the console is opened.
  class SecondFactorsController < BaseController
    skip_before_action :require_second_factor!
    before_action :require_setup, only: %i[verify check]

    def setup
      credential = OperatorCredential.start_for!(current_user)
      return redirect_to operator_verify_path if credential.confirmed?

      render inertia: "operator/setup", props: {
        qr: credential.qr_modules, secret: credential.display_secret, account: current_user.email
      }
    end

    # The recovery codes are rendered, never redirected with, so they are in no address, flash or log.
    def confirm
      credential = OperatorCredential.start_for!(current_user)
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

    def credential = @credential ||= current_user.operator_credential

    # The console's screens are not all Inertia pages (Flightdeck draws its own), so the browser loads the next one whole.
    def open_console(path)
      request.inertia? ? inertia_location(path) : redirect_to(path)
    end

    def require_setup
      redirect_to operator_setup_path unless credential&.confirmed?
    end

    def refusal(credential)
      credential.reload.locked? ? OperatorCredential::LOCKED_MESSAGE : OperatorCredential::WRONG_MESSAGE
    end
  end
end
