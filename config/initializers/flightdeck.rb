# The jobs dashboard of the operator console, behind Operator::BaseController's checks.
Flightdeck.configure do |config|
  config.base_controller_class = "Operator::FlightdeckController"
  config.ui_font = "inter"
end
