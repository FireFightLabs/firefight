require "test_helper"

# Built once here, before the parallel workers fork. Otherwise each worker builds on its first page, and one empties
# the output while another's browser is still loading from it, which leaves pages unstyled or blank.
ViteRuby.commands.build || raise("The Vite build failed, see log/test.log")

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
end
