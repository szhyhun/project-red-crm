require "rails_helper"

RSpec.describe RichTextSanitizer do
  it "keeps the supported formatting tags and removes executable elements" do
    sanitized = described_class.sanitize(
      '<p><strong>Ready</strong><br><em>now</em></p><script>alert("x")</script><iframe src="bad"></iframe>'
    )

    expect(sanitized).to include("<strong>Ready</strong>", "<em>now</em>")
    expect(sanitized).not_to include("script", "iframe", "alert")
  end

  it "removes javascript, data, and vbscript links while keeping safe links" do
    sanitized = described_class.sanitize(
      '<a href="javascript:alert(1)">script</a>' \
      '<a href="data:text/html,<script>x</script>">data</a>' \
      '<a href="vbscript:msgbox(1)">vbscript</a>' \
      '<a href="https://example.test">https</a>' \
      '<a href="/help">relative</a>'
    )

    expect(sanitized).not_to include("javascript:", "data:", "vbscript:")
    expect(sanitized).to include('href="https://example.test"', 'href="/help"')
  end

  it "rejects encoded executable link schemes" do
    expect(described_class.safe_href?("&#x6a;avascript:alert(1)")).to be(false)
    expect(described_class.safe_href?("  HTTPS://example.test/path ")).to be(true)
    expect(described_class.safe_href?("#section")).to be(true)
  end

  it "converts block and line-break markup into readable plain text" do
    expect(described_class.plain_text("<p>First<br>line</p><p>Second</p>")).to eq("First\nline\nSecond")
  end

  it "returns an empty string for blank input" do
    expect(described_class.sanitize(nil)).to eq("")
    expect(described_class.plain_text(" ")).to eq("")
  end
end
