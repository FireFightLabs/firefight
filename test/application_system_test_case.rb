require "test_helper"

# Sheets slide in and dialogs zoom in over a few hundred milliseconds, and a click while one moves lands where the
# button was, not where it is, so a test that clicks straight after a page opens missed it now and then. Capybara
# serves every page with its animations and transitions switched off.
Capybara.disable_animation = true

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include InPlaceHelper

  SCREEN_SIZE = [ 1400, 1400 ].freeze

  driven_by :selenium, using: :headless_chrome, screen_size: SCREEN_SIZE

  # Each worker keeps one browser for all its tests, so a window a test narrowed to a phone's width stayed narrow for
  # whichever test that worker ran next, and that test failed on a layout it was never written for. Every test starts
  # at the full size.
  setup do
    page.current_window.resize_to(*SCREEN_SIZE)
  end

  # Waits for the toast a change says it happened with. A page wide assert_text reads every element's visible text through
  # the browser's main thread, a third of a second on the integrations page here and over a second on a busy CI runner,
  # so polling it while a request is in flight starved the page of the time it needed to follow the redirect and draw
  # the toast. Finding the toast by its own element reads a few words.
  #
  # The toast is drawn only once the server has answered the save, which on a loaded CI runner took longer than
  # Capybara's two second default, so it waits as long as a slow answer can take.
  def assert_toast(text, **options)
    assert_selector "[data-sonner-toast]", text: text, wait: 15, **options
  end

  # Notes the words of every toast as it is drawn, so one that has already gone, or sits hidden behind a newer one, can
  # still be checked. The first toast after a quiet spell arrives inside a new list, so the list's children count too.
  def record_toasts
    page.execute_script(<<~JS)
      document.body.dataset.toastsDrawn = ""
      const recorded = new WeakSet()
      new MutationObserver((mutations) => {
        mutations.flatMap((mutation) => [ ...mutation.addedNodes ]).forEach((node) => {
          if (!(node instanceof Element)) {
            return
          }
          const toasts = node.matches("[data-sonner-toast]") ? [ node ] : [ ...node.querySelectorAll("[data-sonner-toast]") ]
          toasts.filter((toast) => !recorded.has(toast)).forEach((toast) => {
            recorded.add(toast)
            document.body.dataset.toastsDrawn += `${toast.textContent}|`
          })
        })
      }).observe(document.body, { childList: true, subtree: true })
    JS
  end

  def assert_toast_drawn(text)
    assert_selector "body[data-toasts-drawn*='#{text}']", wait: 15
  end
end
