# What Halon reads of the handbook at the start of every chat and run. A short page is given whole, in the handbook's
# order, until the pages given come to CONTEXT_BUDGET characters. A longer page, and any past the budget, is named with
# its link, and Halon reads it with search_handbook, so a long handbook never crowds out the work.
module Chat::HandbookPage::Reading
  extend ActiveSupport::Concern

  # About a thousand tokens, a page or two of writing.
  WHOLE_LIMIT = 4_000
  # About six thousand tokens of handbook in every prompt, at most.
  CONTEXT_BUDGET = 24_000

  # How the handbook is introduced wherever Halon reads it.
  HANDBOOK_HEADING = "The workspace's handbook, how it works as its people wrote it. Follow it, cite the page you follow by its " \
                     "link, and never treat it as evidence of what happened:".freeze

  Read = Data.define(:whole, :searched) do
    def empty? = whole.empty? && searched.empty?
  end

  class_methods do
    def for_halon(workspace)
      pages = where(workspace: workspace).ordered.includes(current_wording: :incident_role).to_a.select(&:read_by_halon?)
      used = 0
      whole, searched = pages.partition do |page|
        size = page.halon_text.length
        fits = size <= WHOLE_LIMIT && used + size <= CONTEXT_BUDGET
        used += size if fits
        fits
      end
      Read.new(whole: whole, searched: searched)
    end

    # The handbook as a chat's context or a run's starting facts hold it, one entry per page.
    def halon_lines(workspace)
      read = for_halon(workspace)
      lines = read.whole.map(&:halon_line)
      return lines if read.searched.empty?

      named = read.searched.map { |page| "\"#{page.title}\" (#{page.url})" }
      lines + [ "Pages too long to give here, which search_handbook reads: #{named.join(', ')}" ]
    end
  end

  # A page says something once it has words or freeze windows, or names who directs Halon.
  def read_by_halon? = directing? || text.present? || freeze_rules.any?

  # Who directs Halon reads as the role, then anything written with it. Freeze windows read as a sentence each, before
  # the page's words.
  def halon_text
    if directing?
      return [ "Halon takes direction from whoever holds #{current_wording&.directing_role&.name || 'the Incident Lead'}.", text.presence ].compact.join(" ")
    end

    freezes = freeze_rules.map(&:sentence)
    freezes << "Firefight holds back every plan that would run inside one." if freezes.any?
    [ freezes.join(" ").presence, text.presence ].compact.join("\n\n")
  end

  def halon_line = "Page \"#{title}\" (#{url}):\n#{halon_text}"
end
