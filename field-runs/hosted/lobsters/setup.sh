#!/usr/bin/env bash
# Hosted setup for one (PR, side) Lobsters tree. Runs after ruby/setup-ruby 4.0.0 and the app checkout.
source "$(dirname "$0")/lib.sh"
EXPECT=$(tree_sha); [ -n "$EXPECT" ] || { echo "SETUP_BLOCK: unknown PR/side $PR/$SIDE"; exit 1; }
cd "$APP_DIR"
L="$OUT/setup.log"
stamp "SETUP_START pr=$PR side=$SIDE tree=$EXPECT" | tee -a "$L"
test "$(git rev-parse HEAD)" = "$EXPECT" || { echo "SETUP_BLOCK: tree sha mismatch" | tee -a "$L"; exit 1; }
echo "TREE $(git rev-parse HEAD) tree-object=$(git rev-parse 'HEAD^{tree}')" | tee -a "$L"
if [ "$SIDE" = head ]; then
  BASE=$(base_sha)
  test "$(git rev-parse HEAD^)" = "$BASE" || { echo "SETUP_BLOCK: head parent is not the recorded base" | tee -a "$L"; exit 1; }
  git cat-file -e "$BASE^{commit}" && git merge-base --is-ancestor "$BASE" HEAD || { echo "SETUP_BLOCK: base object missing or not an ancestor" | tee -a "$L"; exit 1; }
  echo "BASE_OK $BASE is the first parent of head" | tee -a "$L"
fi

# 1. runtime facts, fail closed
{ ruby -v; echo "RUBYLIB=[${RUBYLIB:-}]"; echo "vips=$(pkg-config --modversion vips)"; sqlite3 --version; gem -v; bundle -v; } 2>&1 | tee -a "$L"
case "$(ruby -v)" in "ruby 4.0.0 "*) ;; *) echo "SETUP_BLOCK: ruby is not 4.0.0 (.ruby-version=$(cat .ruby-version))" | tee -a "$L"; exit 1;; esac
[ -z "${RUBYLIB:-}" ] || { echo "SETUP_BLOCK: RUBYLIB must be empty" | tee -a "$L"; exit 1; }
pkg-config --atleast-version=8.13 vips || { echo "SETUP_BLOCK: libvips < 8.13" | tee -a "$L"; exit 1; }

# 2. tool payload: committed gem hash, and byte comparison with a gem built from the pin
test "$(sha256sum "$RECIPE_DIR/saboteur-0.12.3.gem" | cut -d' ' -f1)" = "$GEM_SHA256" || { echo "SETUP_BLOCK: gem hash" | tee -a "$L"; exit 1; }
test "$(git -C "$TOOL_DIR" rev-parse HEAD)" = "$SABOTEUR_PIN" || { echo "SETUP_BLOCK: tool pin" | tee -a "$L"; exit 1; }
rm -rf /tmp/gem-a /tmp/gem-b /tmp/gem-build; mkdir -p /tmp/gem-a /tmp/gem-b /tmp/gem-build
capped 300 gem unpack "$RECIPE_DIR/saboteur-0.12.3.gem" --target /tmp/gem-a >/dev/null
( cd "$TOOL_DIR" && capped 300 gem build saboteur.gemspec --output /tmp/gem-build/saboteur-0.12.3.gem >/dev/null )
capped 300 gem unpack /tmp/gem-build/saboteur-0.12.3.gem --target /tmp/gem-b >/dev/null
rc=0; diff -r /tmp/gem-a/saboteur-0.12.3 /tmp/gem-b/saboteur-0.12.3 > "$OUT/payload-diff.txt" || rc=$?
[ "$rc" = 0 ] || { echo "SETUP_BLOCK: payload differs from the pin build (diff exit $rc)" | tee -a "$L"; head -20 "$OUT/payload-diff.txt"; exit 1; }
echo "PAYLOAD_IDENTICAL files=$(find /tmp/gem-a/saboteur-0.12.3 -type f | wc -l) gem_sha256=$GEM_SHA256" | tee -a "$L"

# 3. instrumentation stages, each preserved byte-for-byte
mkdir -p "$OUT/deps"
cp Gemfile "$OUT/deps/1-Gemfile.original"; cp Gemfile.lock "$OUT/deps/1-Gemfile.lock.original"
PATCH="$RECIPE_DIR/instrumentation/pr$PR-$SIDE.diff"
sha256sum "$PATCH" | tee -a "$L"
git apply --check "$PATCH"; git apply "$PATCH"
cp Gemfile "$OUT/deps/2-Gemfile.patched"; cp Gemfile.lock "$OUT/deps/2-Gemfile.lock.patched-preinstall"
mkdir -p vendor/cache; cp "$RECIPE_DIR/saboteur-0.12.3.gem" vendor/cache/
cp "$RECIPE_DIR/config.saboteur.rb" config/saboteur.rb
[ -f config/database.yml ] || cp config/database.yml.sample config/database.yml
cp config/saboteur.rb "$OUT/deps/config.saboteur.rb"; cp config/database.yml "$OUT/deps/database.yml"

# 4. install (one worker), then prove what was installed
export BUNDLE_JOBS=1 MAKEFLAGS=-j1
rc=0; capped 2400 bundle install --jobs 1 > "$OUT/bundle-install.log" 2>&1 || rc=$?
tail -5 "$OUT/bundle-install.log" | tee -a "$L"
[ "$rc" = 0 ] || { echo "SETUP_BLOCK: bundle install exit $rc" | tee -a "$L"; exit 1; }
cp Gemfile.lock "$OUT/deps/3-Gemfile.lock.installed"
# resolver drift gate: only CHECKSUMS rows of the two added gems may change (python parsed, section aware)
rc=0; diff "$OUT/deps/2-Gemfile.lock.patched-preinstall" "$OUT/deps/3-Gemfile.lock.installed" > "$OUT/deps/lock-install-delta.diff" || rc=$?
[ "$rc" -le 1 ] || { echo "SETUP_BLOCK: lock diff failed (exit $rc)" | tee -a "$L"; exit 1; }
python3 "$RECIPE_DIR/lockgate.py" "$OUT/deps/2-Gemfile.lock.patched-preinstall" "$OUT/deps/3-Gemfile.lock.installed" | tee -a "$L" || { echo "SETUP_BLOCK: unexpected lock change after install" | tee -a "$L"; exit 1; }
bundle list > "$OUT/deps/bundle-list.txt" 2>&1
capped 300 bundle exec ruby -e 'Gem.loaded_specs.sort.each { |n, s| puts "#{n} #{s.version} #{s.full_gem_path}" }' > "$OUT/deps/loaded-specs.txt"
capped 300 bundle exec ruby -e 'require "cgi"; abort("CGI.parse missing") unless CGI.respond_to?(:parse); puts "CGI_PARSE_OK #{Gem.loaded_specs["cgi"]&.version} #{Gem.loaded_specs["cgi"]&.full_gem_path}"' | tee -a "$L"
inst=$(capped 300 bundle exec ruby -e 'puts Gem.loaded_specs["saboteur"].full_gem_path')
for d in lib exe; do
  [ -d "/tmp/gem-a/saboteur-0.12.3/$d" ] || continue
  rc=0; diff -r "/tmp/gem-a/saboteur-0.12.3/$d" "$inst/$d" > "$OUT/deps/installed-$d-diff.txt" || rc=$?
  [ "$rc" = 0 ] || { echo "SETUP_BLOCK: installed saboteur $d differs from the verified payload (exit $rc)" | tee -a "$L"; exit 1; }
  echo "INSTALLED_${d}_IDENTICAL $inst/$d" | tee -a "$L"
done
{ echo "LOCK sha256=$(sha256sum Gemfile.lock | cut -d' ' -f1)"; echo "BUNDLE_LIST sha256=$(sha256sum "$OUT/deps/bundle-list.txt" | cut -d' ' -f1)"; echo "SABOTEUR_BIN $(capped 300 bundle exec saboteur version)"; } | tee -a "$L"

# 5. effective config gate through the tool's own loader
capped 300 bundle exec ruby -rjson -rdigest -e '
require "saboteur"
c = Saboteur::Config.load(root: Dir.pwd, path: nil, overrides: {})
six = %w[integration require rspec_args rails tests coverage_recorder].to_h { |k| [k, c[k]] }
puts "EFFECTIVE " + JSON.generate(six) + " settings=" + Digest::SHA256.hexdigest(JSON.generate(six))
pc = c["partial_coverage"]
puts "EFFECTIVE_partial_coverage=#{pc.inspect}"
exit(1) unless six["rspec_args"].empty? && six["tests"].empty? && pc == "use"' | tee -a "$L" | tee "$OUT/deps/effective-config.txt" >/dev/null
# expected map identity, from the pinned tool's own constants (nothing re-derived by hand)
capped 300 bundle exec ruby -rjson -rdigest -e '
require "saboteur"
c = Saboteur::Config.load(root: Dir.pwd, path: nil, overrides: {})
settings = JSON.generate(Saboteur::Engine::CoverageStore::CACHE_INPUTS.to_h { |k| [k, c[k]] })
puts JSON.generate(root_path: Dir.pwd, root: Digest::SHA256.hexdigest(Dir.pwd), settings: Digest::SHA256.hexdigest(settings),
                   runtime: Saboteur::Engine::CoverageInputsSnapshot.runtime_digest, seed: 3)' > "$OUT/deps/expected-identity.json"
tee -a "$L" < "$OUT/deps/expected-identity.json"
sha256sum config/saboteur.rb | tee -a "$L"
echo "NOTE: partial_coverage=use restores the agreed protocol intent; the original July config bytes were not recovered, so the settings digest cannot prove it." | tee -a "$L"
stamp "SETUP_DONE" | tee -a "$L"
