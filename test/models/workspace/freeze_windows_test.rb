require "test_helper"

class Workspace::FreezeWindowsTest < ActiveSupport::TestCase
  FRIDAYS = { "name" => "Friday afternoons", "repeat" => "weekly", "time_zone" => "Europe/Berlin", "start_day" => 5, "start_time" => "15:00",
              "end_day" => 1, "end_time" => "08:00", "lifted_by" => "the CTO" }.freeze
  YEAR_END = { "name" => "End of year", "repeat" => "once", "time_zone" => "America/New_York", "starts_at" => "2026-12-23T18:00",
               "ends_at" => "2027-01-04T09:00" }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @berlin = ActiveSupport::TimeZone["Europe/Berlin"]
  end

  test "a weekly window runs from its start across the weekend to its end, on its own clock" do
    handbook_page!(@workspace, "Freeze windows", "", freeze_windows: [ FRIDAYS ])

    assert_nil Workspace::FreezeWindows.covering(@workspace, @berlin.parse("2026-10-16 14:59"))
    window = Workspace::FreezeWindows.covering(@workspace, @berlin.parse("2026-10-17 12:00"))
    assert_equal [ @berlin.parse("2026-10-16 15:00"), @berlin.parse("2026-10-19 08:00"), "the CTO" ], [ window.starts_at, window.ends_at, window.lifted_by ]
    assert Workspace::FreezeWindows.covering(@workspace, @berlin.parse("2026-10-19 07:59"))
    assert_nil Workspace::FreezeWindows.covering(@workspace, @berlin.parse("2026-10-19 08:00"))
  end

  test "a window that happens once covers only its own stretch, and only the current wording counts" do
    page = handbook_page!(@workspace, "Freeze windows", "", freeze_windows: [ YEAR_END ])
    new_york = ActiveSupport::TimeZone["America/New_York"]

    assert Workspace::FreezeWindows.covering(@workspace, new_york.parse("2026-12-25 10:00"))
    assert_nil Workspace::FreezeWindows.covering(@workspace, new_york.parse("2027-01-04 09:00"))

    page.write!(text: "No freezes until spring.", by: nil, freeze_windows: [])
    assert_nil Workspace::FreezeWindows.covering(@workspace, new_york.parse("2026-12-25 10:00"))
    assert_equal [ YEAR_END.merge("time_zone" => "America/New_York") ], page.wordings.first.freeze_windows
  end

  test "a plan is refused inside a freeze the handbook sets, saying who may lift it" do
    handbook_page!(@workspace, "Freeze windows", "", freeze_windows: [ FRIDAYS ])
    saturday = @berlin.now.next_occurring(:saturday).change(hour: 12)

    error = assert_raises(Chat::Plan::Refused) { Chat::Plan.send(:check_time!, @workspace, saturday, "Europe/Berlin") }
    assert_match "Changes are frozen for Friday afternoons until Monday", error.message
    assert_match "The CTO may lift it in the handbook.", error.message
  end

  test "Halon reads each window as a sentence before the page's words" do
    page = handbook_page!(@workspace, "Freeze windows", "Hotfixes for an open incident still go out.", freeze_windows: [ FRIDAYS, YEAR_END ])

    assert_equal "Changes are frozen every Friday from 15:00 to Monday 08:00 (Europe/Berlin), for Friday afternoons. The CTO may lift it. " \
                 "Changes are frozen from Wednesday 23 December 2026 at 18:00 to Monday 4 January 2027 at 09:00 (America/New_York), for End of year. " \
                 "Firefight holds back every plan that would run inside one.\n\nHotfixes for an open incident still go out.", page.halon_text
  end

  test "a window that does not hold is refused with a sentence, and never on who directs Halon" do
    page = handbook_page!(@workspace, "Freeze windows", "Ask before a launch.")
    wrong = [ FRIDAYS.merge("time_zone" => "Mars/Olympus"), YEAR_END.merge("ends_at" => "2026-12-01T09:00"), FRIDAYS.merge("name" => "", "start_time" => "25:00") ]

    error = assert_raises(ActiveRecord::RecordInvalid) { page.write!(text: "", by: nil, freeze_windows: wrong) }
    assert_equal [ "Friday afternoons needs a time zone Firefight knows.", "End of year needs to end after it starts.", "Each freeze window needs a name." ],
                 error.record.errors[:base]

    directing = handbook_page!(@workspace, Chat::HandbookPage::DIRECTING_TITLE, "", role: incident_roles(:incident_lead_ws1))
    assert_raises(ActiveRecord::RecordInvalid) { directing.write!(text: "", by: nil, freeze_windows: [ FRIDAYS ]) }
  end
end
