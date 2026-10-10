module HandbookTestHelper
  # A handbook page with its first wording. A role makes it the page saying who directs Halon.
  def handbook_page!(workspace, title, text = "Some words", by: nil, role: nil, freeze_windows: [])
    kind = role ? Chat::HandbookPage::KIND_DIRECTING : Chat::HandbookPage::KIND_WRITTEN
    Chat::HandbookPage.create_written!(workspace, title: title, text: text, by: by, kind: kind, incident_role: role, freeze_windows: freeze_windows)
  end
end
