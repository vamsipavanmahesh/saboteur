# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The HTML report on a real run: the mutation-testing-elements viewer is
# embedded self-contained (works from file://, no network), the report JSON
# round-trips, and - when a Chrome/Chromium binary is available - the
# component actually mounts under file://. CI without a browser still runs
# the structural pins and skips the mount check.
RSpec.describe "report.html viewer (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("people"), "--all") }
  let(:html) { File.binread(File.join(run.dir, ".saboteur", "report.html")) }

  it "embeds the viewer, its pinned bundle and the same JSON report.json holds" do
    expect(run.json).not_to be_nil, run.err
    expect(html).to include('<mutation-test-report-app theme="dark"')
    expect(html).to include("Pinned version: 3.9.0")
    expect(html).not_to match(/<script[^>]*\ssrc\s*=/i)
    expect(html).not_to match(/<link\b/i)
    expect(html).not_to match(%r{<(img|iframe|audio|video|source)[^>]*\ssrc\s*=\s*["']?(?:https?:)?//}i)
    embedded = html[%r{<script type="application/json" id="saboteur-report-json">(.*?)</script>}m, 1]
    # report.json also carries exit-cause/score-gate keys the page build omits.
    parsed = JSON.parse(embedded)
    expect(parsed.values_at("schemaVersion", "files", "testFiles", "skippedSubjects"))
      .to eq(run.json.values_at("schemaVersion", "files", "testFiles", "skippedSubjects"))
  end

  it "mounts the component under file:// when a browser is available" do
    chrome = [ENV.fetch("SABOTEUR_CHROME", nil), "google-chrome", "chromium",
              "chromium-browser"].compact.find do |binary|
      system("which #{binary} > /dev/null 2>&1")
    end
    skip "no Chrome/Chromium binary on this box" unless chrome

    probe = <<~HTML
      <script>
      window.addEventListener("load", function () {
        setTimeout(function () {
          var app = document.querySelector("mutation-test-report-app");
          var ok = !!(app && app.report && app.shadowRoot && app.shadowRoot.childElementCount > 0);
          document.body.insertAdjacentHTML("beforeend",
            '<div id="mount-probe">' + (ok ? "MOUNTED" : "NOT-MOUNTED") + "</div>");
        }, 500);
      });
      </script>
    HTML
    page = File.join(run.dir, "probe.html")
    File.write(page, html.sub("</body></html>", "#{probe}</body></html>"))
    flags = "--headless=new --disable-gpu --no-sandbox --virtual-time-budget=10000 --dump-dom"
    dom = `#{chrome} #{flags} file://#{page} 2>/dev/null`
    expect(dom).to include('<div id="mount-probe">MOUNTED</div>')
  end
end
