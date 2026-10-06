require "test_helper"

# Built once here, before the parallel workers fork. Otherwise each worker builds on its first page, and one empties
# the output while another's browser is still loading from it, which leaves pages unstyled or blank.
ViteRuby.commands.build || raise("The Vite build failed, see log/test.log")

# Sheets slide in and dialogs zoom in over a few hundred milliseconds, and a click while one moves lands where the
# button was, not where it is, so a test that clicks straight after a page opens missed it now and then. Capybara
# serves every page with its animations and transitions switched off.
Capybara.disable_animation = true

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
end
