#!/bin/bash
# preflight.sh <tree> [expected_excluded_spec] - FAIL-CLOSED effective-config gate via the tool's own Config.load.
# No second arg: rspec_args must be []. With an arg: rspec_args must be exactly ["--exclude-pattern", <that spec>] (EX-2 shape).
set -u
T=$1; EXPECT=${2:-}
source ~/field-runs/env400.sh >/dev/null 2>&1
cd ~/field-runs/pr-trees/$T || exit 64
bundle exec ruby -rjson -rdigest -e '
require "saboteur"
expect = ARGV[0]
c = Saboteur::Config.load(root: Dir.pwd, path: nil, overrides: {})
six = %w[integration require rspec_args rails tests coverage_recorder].to_h { |k| [k, c[k]] }
puts "EFFECTIVE rspec_args=#{six["rspec_args"].inspect} tests=#{six["tests"].inspect} settings=#{Digest::SHA256.hexdigest(JSON.generate(six))}"
ok = expect.empty? ? six["rspec_args"].empty? : six["rspec_args"] == ["--exclude-pattern", expect]
exit(1) unless ok && six["tests"].empty?
' "$EXPECT" || { echo "PREFLIGHT_BLOCK: effective rspec_args mismatch (expect='${EXPECT:-none}') in $T - refusing launch"; exit 1; }
echo "PREFLIGHT_OK $T expect='${EXPECT:-none}' $(date -Iseconds) lock=$(sha256sum Gemfile.lock | cut -c1-16)"
