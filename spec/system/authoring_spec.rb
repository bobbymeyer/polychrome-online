# frozen_string_literal: true

require "rails_helper"

# The authoring pages' own JavaScript, in a real browser: the monster form's columns, its live readings, the draft the
# browser keeps, the choices refresh, and the search shortcut. The pages' server side is in spec/requests.
RSpec.describe "Authoring in the browser", type: :system do
  let(:world) { base_world }
  let(:goblin) { world.monsters.find_by!(slug: "goblin") }
  let(:editor) { make_user("Editor", admin: true) }
  let(:draft_key) { "draft:edit:base:bestiary:goblin" }

  before { sign_in_through_the_page(editor) }

  def edit_goblin = visit(edit_world_bestiary_monster_path(world, goblin))

  # The rule row that is blank on the form to begin with: its select and inputs are named by its number.
  def first_blank_rule = goblin.ai_script.size + 1

  def stored(key) = page.evaluate_script("localStorage.getItem('#{key}')")

  # Waits for the browser to have kept (or dropped) a draft, which it does a moment after typing.
  def wait_until_stored(key, present: true)
    page.document.synchronize { raise Capybara::ExpectationNotMet, "draft #{present ? 'not kept' : 'still kept'}" unless stored(key).present? == present }
  end

  describe "the monster form's AI script" do
    it "keeps the columns most rules skip out of the way, and brings them out for the rule that needs one" do
      edit_goblin
      expect(page).to have_no_css("th[data-advanced]")
      click_on "More conditions"
      expect(page).to have_css("th[data-advanced]", count: 4)
      expect(page).to have_button("Fewer conditions")

      click_on "Fewer conditions"
      expect(page).to have_no_css("th[data-advanced]")
      find("select[aria-label='When, rule #{first_blank_rule}']").select("When hit") # "By" is one of them
      expect(page).to have_css("th[data-advanced]", text: "By")
    end

    it "reads the rules back in words as they are typed" do
      edit_goblin
      n = first_blank_rule
      find("select[aria-label='Use, rule #{n}']").select("Fire")
      find("input[aria-label='Own HP below, rule #{n}']").fill_in(with: "30")
      expect(page).to have_css("#monster_script_reading", text: "If own HP below 30%: Fire")

      find("input[aria-label='Own HP below, rule #{n}']").fill_in(with: "")
      expect(page).to have_css("#monster_script_reading", text: /Otherwise:\s+Fire/)
    end

    it "pulls an entry made since the page loaded into the selects, keeping what is chosen" do
      edit_goblin
      find("select[aria-label='Use, rule #{first_blank_rule}']").select("Fire")
      create_item(world, slug: "zed_elixir", name: "Zed Elixir", category: "consumable", stats: {}, target: "single_ally",
                         effects: [ { primitive: "heal", power: 30 } ])
      expect(page).to have_no_css("select[aria-label='Drop item 1'] option", text: "Zed Elixir")

      within(find(".missing", text: "New item")) { click_on "Refresh the choices" }
      expect(page).to have_css("select[aria-label='Drop item 1'] option", text: "Zed Elixir")
      expect(find("select[aria-label='Use, rule #{first_blank_rule}']").value).to eq("fire")
      expect(page).to have_text("Choices refreshed.")
    end
  end

  describe "how it fares" do
    it "tries the saved version once the form is in view, and the form as it stands when a stat changes" do
      edit_goblin
      expect(page).to have_css("#monster_strength", text: "Trying the saved version") # fetched when it comes into view
      page.scroll_to(find("#stat-block"))
      expect(page).to have_css("#monster_strength", text: "Over 10 more rolls against a level-5 party", wait: 15)

      find("#monster_stats_max_hp").fill_in(with: "400")
      expect(page).to have_css("#monster_strength", text: "As it stands, 2 × Goblin", wait: 20)
      expect(page).to have_css("#monster_strength tr.is-current td", text: "Goblin")
    end
  end

  describe "the draft the browser keeps" do
    it "offers back what was typed, including rows added, and puts it back only when asked" do
      edit_goblin
      n = first_blank_rule + 2 # a third blank row, added here
      fill_in "monster_name", with: "Goblin Draft"
      within("#behavior") { click_on "Add a row" }
      find("select[aria-label='Use, rule #{n}']").select("Fire")
      wait_until_stored(draft_key)

      edit_goblin
      expect(page).to have_css(".draft-notice", text: "were kept in this browser and never saved")
      expect(find("#monster_name").value).to eq("Goblin") # nothing put back on its own
      click_on "Put them back"
      expect(page).to have_no_css(".draft-notice")
      expect(find("#monster_name").value).to eq("Goblin Draft")
      expect(find("select[aria-label='Use, rule #{n}']").value).to eq("fire")
    end

    it "lets it go when asked, and when the entry is saved" do
      edit_goblin
      fill_in "monster_name", with: "Goblin Draft"
      wait_until_stored(draft_key)
      edit_goblin
      click_on "Throw them away"
      expect(page).to have_no_css(".draft-notice")
      expect(stored(draft_key)).to be_nil

      fill_in "monster_name", with: "Goblin Saved"
      wait_until_stored(draft_key)
      click_on "Save changes"
      expect(page).to have_text("Goblin Saved was updated.")
      wait_until_stored(draft_key, present: false)
    end
  end

  describe "a refused save" do
    it "brings the problems into view and focuses them" do
      edit_goblin
      find("#monster_stats_max_hp").fill_in(with: "0")
      click_on "Save changes"
      expect(page).to have_css(".form-errors a[href='#stat-block']")
      expect(page.evaluate_script("document.activeElement.classList.contains('form-errors')")).to be(true)
    end
  end

  describe "the art slot" do
    it "shows a picture as soon as it is chosen" do
      edit_goblin
      attach_file "monster_image", Rails.root.join("spec/fixtures/files/goblin.png").to_s
      expect(page).to have_css("[data-image-preview-target=slot] img[alt='The picture chosen, not yet saved']")
    end
  end

  describe "searching the books" do
    it "takes / to the search box, and Enter to the results" do
      visit world_path(world)
      find("body").send_keys("/")
      expect(page.evaluate_script("document.activeElement.name")).to eq("q")
      page.driver.browser.switch_to.active_element.send_keys("zzzz", :enter)
      expect(page).to have_current_path(/search\?q=zzzz/)
      expect(page).to have_text("Nothing in Base World's books is called “zzzz”")
    end
  end
end
