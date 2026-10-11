# Stands in for the hosted build's credits checkout, which lives outside this repo. Opening a pack goes to a payment
# page with Pay and Back, the way the payment provider's does. Pay confirms like the hosted build, adding the credit and
# sending the buyer to where they came from with its notice. Back returns them there with nothing changed.
module CreditCheckoutTestHelper
  PAY_PATH = "/test/credits/pay".freeze
  CONFIRM_PATH = "/test/credits/confirm".freeze
  ADDED = "Credits added. The balance is now $50.00.".freeze

  class CheckoutsController < InertiaController
    include ReturnTo

    skip_before_action :block_inaccessible_workspace

    def create
      url = "#{PAY_PATH}?#{{ pack: params[:pack], return_to: return_to_param }.to_query}"
      request.inertia? ? inertia_location(url) : redirect_to(url)
    end

    def pay
      back = return_to_param || dashboard_path
      paid = "#{CONFIRM_PATH}?#{{ return_to: back }.to_query}"
      render html: helpers.safe_join([
        helpers.tag.h1("Pay for $#{params[:pack].to_i / 100} of credits"),
        helpers.link_to("Pay", paid), " ", helpers.link_to("Back", back)
      ])
    end

    def confirm
      credit = Entitlements.ai_credit(current_workspace)
      credit.spendable = true
      credit.balance = "$50.00"
      redirect_to return_to_param || dashboard_path, notice: ADDED
    end
  end

  # Drawn once in a test process, ahead of the catch-all, and left in place since nothing else uses these paths.
  def draw_credit_checkout!
    return if CreditCheckoutTestHelper.drawn

    controller = "credit_checkout_test_helper/checkouts"
    Rails.application.routes.prepend do
      post AiAccountTestHelper::CHECKOUT_PATH, to: "#{controller}#create"
      get PAY_PATH, to: "#{controller}#pay"
      get CONFIRM_PATH, to: "#{controller}#confirm"
    end
    Rails.application.reload_routes!
    CreditCheckoutTestHelper.drawn = true
  end

  class << self
    attr_accessor :drawn
  end
end
