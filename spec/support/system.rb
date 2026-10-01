# frozen_string_literal: true

# System specs (spec/system): the live pages in a real, headless Chrome.
#
# Chrome is found by Selenium Manager, or set CHROME_BIN to use a
# particular one (a Chromium without its own driver gets a matching one
# downloaded).
#
# The pages need what the request specs stub out: Action Cable delivering
# broadcasts to the browser (the async adapter, in this process) and jobs
# running (page refreshes are broadcast from a job). Both go back to the
# test adapters afterwards, which the have_broadcasted_to and
# have_enqueued_job matchers need.
module SystemHelpers
  def sign_in_through_the_page(user)
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: SignIn::PASSWORD
    click_on "Sign in"
    expect(page).to have_no_current_path(new_session_path)
  end

  # Sign in and sit down at the example's campaign, in this person's own
  # browser (a Capybara session per person).
  def seat(user, seat)
    Capybara.using_session(user.name) do
      sign_in_through_the_page(user)
      sit_at(campaign, seat)
    end
  end

  # Look through this person's browser.
  def as(user, &) = Capybara.using_session(user.name, &)

  # A line in the table's log (in the drawer, so maybe not on screen).
  def logged?(text) = have_css("#chat_log li", text: text, visible: :all)

  # Sit at a campaign's table: "gm", a character, or nil to stand up.
  def sit_at(campaign, seat)
    visit campaign_table_path(campaign)
    # Whoever has an obvious seat (the GM, a player's only character) is
    # already in it: stand up first.
    click_on "Change seat" if page.has_button?("Change seat", wait: 2)
    return wait_for_streams unless seat

    within("section", text: "Take a seat") { click_on(seat == "gm" ? "Game Master" : seat.name, match: :prefer_exact) }
    # The GM's seat is said under the name; a player's is the "You" line (their Change seat is in the menu).
    expect(page).to(seat == "gm" ? have_text("At the table as GM") : have_css(".table-you", text: seat.name))
    wait_for_streams
  end

  # A page hears broadcasts only once its streams have subscribed: wait for
  # that before changing anything it should hear about.
  def wait_for_streams
    expect(page).to have_css("turbo-cable-stream-source", visible: :all)
    expect(page).to have_no_css("turbo-cable-stream-source:not([connected])", visible: :all, wait: 5)
  end
end

RSpec.configure do |config|
  config.include SignIn, type: :system
  # Several browsers and a live connection each: give pages time to settle.
  config.before(:suite) { Capybara.default_max_wait_time = 5 if defined?(Capybara) }
  config.include SystemHelpers, type: :system

  # A chosen Chrome gets a driver of its own version, not whichever one is
  # on the PATH.
  config.before(:suite) do
    chrome = ENV.fetch("CHROME_BIN", "")
    next if chrome.empty? || !defined?(Selenium::WebDriver)

    paths = Selenium::WebDriver::SeleniumManager.binary_paths("--browser", "chrome", "--browser-path", chrome, "--skip-driver-in-path")
    Selenium::WebDriver::Chrome::Service.driver_path = paths["driver_path"]
  end

  config.before(:each, type: :system) do
    # Each example starts with nothing remembered in the browser (a pinned log, the GM's open tab, cards seen).
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ],
                         options: { clear_local_storage: true, clear_session_storage: true } do |options|
      options.binary = ENV["CHROME_BIN"] unless ENV.fetch("CHROME_BIN", "").empty?
      options.add_argument("--no-sandbox") if Process.uid.zero? # Chrome won't sandbox as root (containers)
      options.add_argument("--disable-dev-shm-usage")
    end
  end

  config.around(:each, type: :system) do |example|
    cable = ActionCable.server
    was = cable.config.cable
    cable.config.cable = { "adapter" => "async" }
    cable.restart
    jobs = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
  ensure
    ActiveJob::Base.queue_adapter = jobs
    cable.config.cable = was
    cable.restart
  end
end
