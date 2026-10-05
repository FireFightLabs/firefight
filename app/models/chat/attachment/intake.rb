# What Halon will read of a file, worked out once as it arrives: the text of a text file or a PDF, with anything that
# looks like a credential replaced first, how many were, and how many pages a PDF has.
module Chat::Attachment::Intake
  Read = Data.define(:text, :redactions, :page_count)

  SAMPLE = 8_192
  # A log in a legacy encoding still reads as text with a few unreadable bytes. A binary file has many.
  UNREADABLE_SHARE = 0.02
  UNREADABLE = "�".freeze

  def self.read(kind, bytes, name)
    case kind
    when Chat::Attachment::KIND_TEXT then redacted(as_text(bytes))
    when Chat::Attachment::KIND_PDF then pdf(bytes, name)
    else Read.new(text: nil, redactions: 0, page_count: nil)
    end
  end

  def self.text_bytes?(bytes)
    sample = as_text(bytes.byteslice(0, SAMPLE))
    return false if sample.include?("\u0000")

    sample.count(UNREADABLE) <= sample.length * UNREADABLE_SHARE
  end

  def self.as_text(bytes)
    bytes.dup.force_encoding(Encoding::UTF_8).scrub(UNREADABLE).delete_prefix("﻿")
  end

  # The transcript's secret patterns, the same ones every tool result passes through before a model reads it.
  def self.redacted(text, page_count: nil)
    found = Chat::SecretFree::SECRET_PATTERNS.values.sum { |pattern| text.scan(pattern).size }
    Read.new(text: Chat::SecretFree.redacted(text), redactions: found, page_count: page_count)
  end

  # A PDF that cannot be opened is refused, since a provider handed one would refuse the whole chat after it.
  def self.pdf(bytes, name)
    require "pdf-reader"
    Timeout.timeout(Chat::Attachment::READ_TIMEOUT) do
      reader = PDF::Reader.new(StringIO.new(bytes))
      pages = reader.pages.first(Chat::Attachment::PDF_PAGES).map { |page| page_text(page) }
      text = pages.any?(&:present?) ? pages.each_with_index.map { |said, index| "[Page #{index + 1}]\n#{said}" }.join("\n\n") : ""
      redacted(text, page_count: reader.page_count)
    end
  rescue PDF::Reader::EncryptedPDFError
    raise Chat::Attachment::Refused, "#{name} is password protected, so Halon cannot open it."
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError, Timeout::Error
    raise Chat::Attachment::Refused, "#{name} could not be opened as a PDF."
  end

  # A page drawn in a way the reader does not follow has no text, and the rest of the document still reads.
  def self.page_text(page)
    page.text.strip
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
    ""
  end
  private_class_method :page_text
end
