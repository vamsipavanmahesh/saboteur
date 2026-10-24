# Lobsters CGI.parse failure: upstream investigation (2026-10-24)

**Verdict: the CGI.parse removal is known upstream and was fixed in January 2026 (issue #1845, PR #1846). Our observed failure is a sandbox environment artifact, not an app bug and not a cgi-gem regression. No new upstream issue is warranted on current evidence. A conditional standby draft is included at the bottom.**

Investigator: field-run support. All upstream reads were public and unauthenticated (GitHub REST API, raw.githubusercontent.com, rubygems.org). Nothing was posted upstream.

## 1. What we observed (raw evidence)

- Baseline at pinned SHA 407536444934ac7d78f4ce1c18f228e3891a8663 ("bump for Ruby joining this week's CVE-a-thon", 2026-10-23T15:06:27Z, = origin/main at qualification), Ruby 4.0.9 (ruby-builder prebuilt, revision 3e93b23afc), `bundle exec rspec` full suite: 913 examples, 2 failures, wall 35.345s, exit 1 (logs/baseline-rspec.json).
- CGI failure: `rspec ./spec/extras/github_spec.rb:14` "Github CGI.parse should work", NoMethodError "undefined method 'parse' for class CGI", backtrace pointing at **spec line 15** (`expect(CGI.parse("a"))`).
- Provenance note: the failing line is the sentinel spec (spec/extras/github_spec.rb:15), NOT the app callsite. The app callsite is extras/github.rb:21 (`ps = CGI.parse(res)` inside `Github.token_and_user_from_code`, GitHub account linking). That callsite was never executed by the failing example.
- Reproduced in: full baseline + 2 isolated rechecks (2026-10-23 21:55-21:56 IST) + fresh post-rebuild rerun of the 2 red files, 7 examples, 2 failures, exit 1, wall 7.56s (2026-10-24 06:38 IST). Repeated observations, not a formal non-flakiness proof; the cause is now explained structurally, so flakiness is moot for this failure.
- The second baseline failure (spec/features/user_administration_spec.rb:39 "banning", Expected 0 to eq 1) is a separate matter, see section 6 note.

## 2. Upstream history: this failure class is known and fixed

- Issue #1845 "Can't link GitHub accounts because CGI.parse is gone" (opened by pushcx 2026-01-04, closed as completed 2026-01-07): https://github.com/lobsters/lobsters/issues/1845
- Fix PR #1846 "`CGI.parse("oops")`" (caius, merged 2026-01-07, merge commit 708c4e1224cfda31b666aedca14d305f3287ce01): https://github.com/lobsters/lobsters/pull/1846
  - Fix approach: add `gem "cgi"` to the Gemfile (the rubygems cgi gem still provides the full library) plus a sentinel spec proving CGI.parse loads. That sentinel is the exact spec failing in our sandbox.
- Verified at pinned SHA and at current master (identical): Gemfile line 35 `gem "cgi"`; Gemfile.lock pins cgi 0.5.1 (sha256 e93fcafc69b8a934fe1e6146121fa35430efa8b4a4047c4893764067036f18e9), byte-identical to the lockfile at the January fix merge.

## 3. Claim check: "CGI.parse was removed in cgi 0.5.1" is FALSE

The field-run report attributed the failure to cgi gem 0.5.1 removing CGI.parse. Verified against the actual artifacts:

- Downloaded cgi 0.4.2, 0.5.0, 0.5.1, 0.5.2 from rubygems.org. ALL FOUR define `CGI.parse` (lib/cgi/core.rb) and their lib/cgi.rb requires cgi/core. The 0.5.1 gem shipped and installed by the field run does provide CGI.parse.
- Rubygems release dates: 0.5.0 (2025-06-04), 0.5.1 (2025-12-10), 0.5.2 (2026-06-23). https://rubygems.org/gems/cgi/versions
- The actual removal is in Ruby 4.0's stdlib, not the gem. Ruby 4.0.9's built-in lib/ruby/4.0.0/cgi.rb is a short shim: it requires only cgi/escape and warns "CGI library is removed from Ruby 4.0. Please use cgi/escape instead... If you need to use the full features of CGI library, Please install cgi gem." Verified byte-for-byte on the exact ruby-builder Ruby 4.0.9 used by the field run; the same shim exists in the ruby-builder Ruby 4.0.0 build. (Ruby 4.0.0 release notes' stdlib-compatibility section, referenced by #1845: https://www.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/)

## 4. Why our run failed anyway: RUBYLIB shadowing (proven on the identical Ruby build)

- The ruby-builder prebuilt tarball's compiled-in prefix (/opt/hostedtoolcache/Ruby/4.0.9/x64) does not exist in the sandbox, so the field-run environment sets RUBYLIB to the extracted tree's stdlib dirs (recorded in env.sh / ENV.md).
- RUBYLIB directories precede activated gem paths in $LOAD_PATH. Measured on the same build with the cgi 0.5.1 gem activated: $LOAD_PATH front = stdlib dirs, THEN the gem's lib.
- So `require "cgi"` resolved to Ruby's stdlib removal-shim, which defines only the escape functions; CGI.parse stayed undefined and the sentinel spec failed.
- Proof on the identical ruby-builder Ruby 4.0.9, cgi 0.5.1 gem installed from rubygems:
  - Worker-style RUBYLIB (shim first): `CGI.respond_to?(:parse)` = false (reproduces the baseline failure).
  - Gem lib first (`-I`, exactly what bundler/setup achieves on a standard install): parse = true, `CGI::VERSION` = "0.5.1".
  - Shim renamed away, worker-style RUBYLIB kept: parse = true, VERSION = "0.5.1".
- Conclusion: baseline failure F-BASE-1 is an artifact of the sandbox Ruby layout. On a correctly installed Ruby 4.0.9, lobsters' January fix still works. The app code at extras/github.rb:21 is fine.
- Suggested sandbox fix for the field worker: in the writable extracted ruby tree, rename lib/ruby/4.0.0/cgi.rb and lib/ruby/4.0.0/cgi/ aside (verified working above), or install Ruby 4.0.9 at a proper prefix. Then re-run the baseline. Caveat: renaming the shim means `require "cgi"` without the gem raises LoadError instead of warning; acceptable inside this sandbox since the app Gemfile always provides the gem.

## 5. Upstream CI status (checked 2026-10-24 ~06:40 UTC)

- 2026-10-12, run 38323119585 (commit ab6fe2424, Ruby 4.0.0 era, same cgi 0.5.1 lockfile): test job SUCCESS; lint and security success; database-consistency failure. The mid-October main redness was the database-consistency job, not the test suite. https://github.com/lobsters/lobsters/actions/runs/38323119585
- 2026-10-23T15:06Z, run 39975413405 at the pinned commit 40753644 (the .ruby-version 4.0.0 -> 4.0.9 bump): test, lint, database-consistency FAILURE; security success. The "Check Dockerfile Ruby version" workflow also failed at that run. Previous main run 39975056886 (f6cba972a) failed all four jobs. https://github.com/lobsters/lobsters/actions/runs/39975413405
- Job logs are not publicly readable (API returns 403 "Must have admin rights"; the HTML page does not render logs without JS), so the CAUSE of the red test job at the pinned commit is UNCONFIRMED. Plausible candidates: ruby/setup-ruby not yet serving the hours-old Ruby 4.0.9, or a genuine 4.0.9 regression. Do not quote either as fact.
- No open upstream issue covers a CGI regression or the current CI red: all 11 cgi-tagged issues/PRs were reviewed (latest relevant are #1845/#1846 from January), and ~30 recent issues (Sept-Oct 2026) contain nothing about CGI or the failing suite.

## 6. Recommendation

1. Do NOT file a new upstream issue now. The CGI.parse removal is known and fixed upstream; our instance is a local environment artifact. Filing would be a duplicate/noise report to a maintainer who already handled it.
2. Fix the sandbox Ruby layout (section 4) and re-run the two red specs. Expected: github_spec goes green. If it STILL fails on a correctly installed Ruby 4.0.9, that is a genuine 4.0.9 regression of the #1846 fix - then file the standby draft in section 7, ideally after the upstream CI red cause is known.
3. Note on F-BASE-2 (banning spec, no email sent): separate, deterministic-looking failure, NOT CGI-related. Leads worth checking before calling it app-real: pinned tree is mid-repair of its email subsystem (parent commit e646f63a "restore transactional + notifications email; not yet mailing list mode", 2026-10-21) and upstream has open issues #2263 "Reply notifications are not being sent any more" (2026-10-21) and #2264 invitation email errors (2026-10-21). Possible relation, unverified. https://github.com/lobsters/lobsters/issues/2263

## 7. Standby issue draft - file ONLY if the sentinel still fails on a correctly installed Ruby 4.0.9

Title: CGI.parse sentinel spec fails on Ruby 4.0.9 (spec/extras/github_spec.rb)

Body:

```
Following up on #1845 / #1846.

On Ruby 4.0.9 (.ruby-version at current main, 40753644), the sentinel spec
added in #1846 fails:

    bundle exec rspec spec/extras/github_spec.rb

    Github CGI.parse should work
    Failure/Error: expect(CGI.parse("a"))
    NoMethodError: undefined method 'parse' for class CGI
    # ./spec/extras/github_spec.rb:15

The Gemfile still has `gem "cgi"` and Gemfile.lock pins cgi 0.5.1, which
does provide CGI.parse, so this looks like Ruby 4.0.9's stdlib cgi shim
shadowing the gem rather than the removal #1846 fixed.

extras/github.rb:21 uses CGI.parse in Github.token_and_user_from_code, so
GitHub account linking would raise at runtime if this reproduces outside
the test suite.

Environment: ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM
[x86_64-linux], bundler 4.0.3, cgi 0.5.1 from rubygems.
```

(If filed, add whether CI run https://github.com/lobsters/lobsters/actions/runs/39975413405 fails for the same reason once its logs are readable.)

## Source URLs

- https://github.com/lobsters/lobsters/issues/1845
- https://github.com/lobsters/lobsters/pull/1846
- https://github.com/lobsters/lobsters/commit/407536444934ac7d78f4ce1c18f228e3891a8663
- https://github.com/lobsters/lobsters/blob/407536444934ac7d78f4ce1c18f228e3891a8663/extras/github.rb
- https://github.com/lobsters/lobsters/blob/407536444934ac7d78f4ce1c18f228e3891a8663/spec/extras/github_spec.rb
- https://github.com/lobsters/lobsters/blob/407536444934ac7d78f4ce1c18f228e3891a8663/Gemfile
- https://github.com/lobsters/lobsters/actions/runs/39975413405
- https://github.com/lobsters/lobsters/actions/runs/38323119585
- https://rubygems.org/gems/cgi/versions
- https://www.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/
- https://github.com/lobsters/lobsters/issues/2263
