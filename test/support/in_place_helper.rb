# A change made on a page stays on it: the page is never visited whole, and what the change reads back is only the props
# it named. watch_page marks the page and records each request Inertia sends with the props it asks for, and
# assert_stayed_in_place checks the mark survived and every change sent since asked for exactly those props.
module InPlaceHelper
  RECORDER = <<~JS.freeze
    window.stillTheSamePage = true;
    window.inertiaChanges = [];
    if (!XMLHttpRequest.prototype.recordsInertia) {
      XMLHttpRequest.prototype.recordsInertia = true;
      const open = XMLHttpRequest.prototype.open;
      const setRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
      const send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url, ...rest) {
        this.recorded = { method: String(method).toLowerCase(), url: String(url), headers: {} };
        return open.call(this, method, url, ...rest);
      };
      XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
        if (this.recorded) { this.recorded.headers[name] = value; }
        return setRequestHeader.call(this, name, value);
      };
      XMLHttpRequest.prototype.send = function (...args) {
        if (this.recorded && this.recorded.headers["X-Inertia"] && this.recorded.method !== "get" && window.inertiaChanges) {
          window.inertiaChanges.push({ url: this.recorded.url, only: this.recorded.headers["X-Inertia-Partial-Data"] || null });
        }
        return send.call(this, ...args);
      };
    }
  JS

  # Every request Inertia sends from here waits before it leaves, as a slow server would, and the page notes whether its
  # progress bar was ever shown and how many requests are still out.
  SLOW_SERVER = <<~JS.freeze
    window.progressShown = false;
    window.requestsOut = 0;
    setInterval(() => {
      const bar = document.getElementById("nprogress");
      if (bar && bar.checkVisibility()) { window.progressShown = true; }
    }, 10);
    const sendNow = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function (...args) {
      window.requestsOut += 1;
      this.addEventListener("loadend", () => { window.requestsOut -= 1; });
      setTimeout(() => sendNow.call(this, ...args), DELAY);
    };
  JS

  def watch_page
    page.execute_script(RECORDER)
  end

  def slow_server(seconds)
    page.execute_script(SLOW_SERVER.sub("DELAY", (seconds * 1000).to_i.to_s))
  end

  def requests_out = page.evaluate_script("window.requestsOut")

  def assert_no_progress_bar
    assert_equal false, page.evaluate_script("window.progressShown"), "the page's progress bar showed"
  end

  # Each change sent since the page was watched asked for the named props alone, and the page was never replaced.
  def assert_stayed_in_place(only:)
    changes = page.evaluate_script("window.inertiaChanges")
    assert page.evaluate_script("window.stillTheSamePage === true"), "the page was visited whole"
    assert changes.present?, "no change was sent"
    changes.each do |change|
      assert change["only"], "#{change['url']} read the whole page back"
      assert_equal Array(only).sort, change["only"].split(",").uniq.sort, "#{change['url']} read back more or less than it changed"
    end
  end
end
