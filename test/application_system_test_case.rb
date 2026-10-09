require "test_helper"

# Sheets slide in and dialogs zoom in over a few hundred milliseconds, and a click while one moves lands where the
# button was, not where it is, so a test that clicks straight after a page opens missed it now and then. Capybara
# serves every page with its animations and transitions switched off.
Capybara.disable_animation = true

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  SCREEN_SIZE = [ 1400, 1400 ].freeze

  driven_by :selenium, using: :headless_chrome, screen_size: SCREEN_SIZE

  # Each worker keeps one browser for all its tests, so a window a test narrowed to a phone's width stayed narrow for
  # whichever test that worker ran next, and that test failed on a layout it was never written for. Every test starts
  # at the full size.
  setup do
    page.current_window.resize_to(*SCREEN_SIZE)
  end
end
