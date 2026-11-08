require "test_helper"

# Selenium Manager only auto-downloads x86_64 chromedriver builds — Google
# doesn't publish a Linux arm64 one — so on the arm64 dev container it
# fetches a binary that can't execute at all. The Debian chromium-driver
# package installs one built for this platform; prefer it when present
# and let Selenium Manager auto-download everywhere else (e.g. CI's
# x86_64 runners, which have no such mismatch).
if File.exist?("/usr/bin/chromedriver")
  Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # --no-sandbox/--disable-dev-shm-usage are needed because the dev
  # container (and CI runners in some setups) run Chrome as root, where
  # Chrome's sandbox refuses to start at all. Harmless when not running
  # as root.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_option|
    driver_option.add_argument("--no-sandbox")
    driver_option.add_argument("--disable-dev-shm-usage")
    driver_option.binary = "/usr/bin/chromium" if File.exist?("/usr/bin/chromium")
  end

  # CI's headless Chrome occasionally stalls on a page load and the
  # WebDriver call times out (Net::ReadTimeout — PendingDecisionsTest,
  # 2026-11-03 and -06, on the very first visit). Retry once with a fresh
  # browser rather than fail the run; a second stall still fails.
  def visit(...)
    super
  rescue Net::ReadTimeout
    page.driver.quit
    super
  end
end
