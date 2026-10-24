#!/usr/bin/env bash
# prep.sh <app_sha>: build the tool from the pin, put the app at the fixed canonical root, integrate, install, prove.
source "$(dirname "$0")/lib.sh"
SHA=${1:?app sha}; [[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "PREP_BLOCK: bad sha"; exit 1; }
L="$OUT/prep.log"; mkdir -p "$OUT/deps"
stamp "PREP_START sha=$SHA root=$APP_ROOT" | tee -a "$L"
# 1. tool payload built in this job from the exact pin, compared with the source tree (nothing committed, nothing from a registry)
test "$(git -C "$TOOL_DIR" rev-parse HEAD)" = "$SABOTEUR_PIN" || { echo "PREP_BLOCK: tool pin" | tee -a "$L"; exit 1; }
rm -rf /tmp/gem-build /tmp/gem-b; mkdir -p /tmp/gem-build /tmp/gem-b
( cd "$TOOL_DIR" && capped 300 gem build saboteur.gemspec --output /tmp/gem-build/saboteur-0.12.3.gem >/dev/null )
capped 300 gem unpack /tmp/gem-build/saboteur-0.12.3.gem --target /tmp/gem-b >/dev/null
for d in lib exe; do
  [ -d "$TOOL_DIR/$d" ] || continue
  rc=0; diff -r "$TOOL_DIR/$d" "/tmp/gem-b/saboteur-0.12.3/$d" > "$OUT/deps/payload-$d-diff.txt" || rc=$?
  [ "$rc" = 0 ] || { echo "PREP_BLOCK: built gem $d differs from the pin source tree" | tee -a "$L"; exit 1; }
done
GEMSHA=$(sha256sum /tmp/gem-build/saboteur-0.12.3.gem | cut -d' ' -f1)
echo "PAYLOAD_FROM_PIN gem_sha256=$GEMSHA files=$(find /tmp/gem-b/saboteur-0.12.3 -type f | wc -l) (built in this job; differs by build environment from earlier handoff gems, compared to source, not to a committed hash)" | tee -a "$L"
# 2. app at the fixed canonical root, exact sha
if [ ! -d "$APP_ROOT/.git" ]; then
  sudo mkdir -p "$APP_ROOT"; sudo chown "$(id -u):$(id -g)" "$APP_ROOT"
  capped 1800 git clone --quiet https://github.com/rubyforgood/human-essentials.git "$APP_ROOT"
fi
cd "$APP_ROOT"
git reset -q --hard; git clean -qfdx   # serial reuse of one root; nothing carried over except what the workflow restores afterwards
git checkout -q --detach "$SHA"
test "$(git rev-parse HEAD)" = "$SHA" || { echo "PREP_BLOCK: HEAD != $SHA" | tee -a "$L"; exit 1; }
test "$(realpath "$APP_ROOT")" = "$APP_ROOT" || { echo "PREP_BLOCK: app root is not canonical" | tee -a "$L"; exit 1; }
LOCKB=$(tail -n1 Gemfile.lock | tr -d ' '); [[ "$LOCKB" =~ ^[0-9]+(\.[0-9]+)+$ ]] || { echo "PREP_BLOCK: lock has no BUNDLED WITH version" | tee -a "$L"; exit 1; }
export BUNDLER_VERSION=$LOCKB
capped 600 gem install bundler -v "$LOCKB" --no-document 2>&1 | tail -2 | tee -a "$L"
echo "BUNDLER_FROM_LOCK $LOCKB (runner default: $(gem list -i bundler -v '>= 0' >/dev/null 2>&1 && gem list bundler 2>/dev/null | head -1))" | tee -a "$L"
echo "APP HEAD=$SHA tree=$(git rev-parse 'HEAD^{tree}') root=$(realpath .)" | tee -a "$L"
# 3. runtime
{ ruby -v; gem -v; bundle -v; node -v 2>&1 || true; google-chrome --version 2>&1 || chromium --version 2>&1 || true; psql --version 2>&1 || true; } 2>&1 | tee -a "$L"
case "$(ruby -v)" in "ruby 3.4.3 "*) ;; *) echo "PREP_BLOCK: ruby is not 3.4.3 (.ruby-version=$(cat .ruby-version 2>/dev/null))" | tee -a "$L"; exit 1;; esac
# 3b. browser is required by the system specs: record it, block when absent
BR=$(command -v google-chrome || command -v chromium || command -v chromium-browser || true)
[ -n "$BR" ] || { echo "PREP_BLOCK: no Chrome/Chromium executable for Cuprite" | tee -a "$L"; exit 1; }
echo "BROWSER $BR $("$BR" --version 2>&1)" | tee -a "$L"
{ echo "CI=${CI:-unset} RAILS_ENV=${RAILS_ENV} PG_HOST=${PG_HOST} PG_USERNAME=${PG_USERNAME} NOT_HEADLESS=${NOT_HEADLESS:-unset} DOCKER=${DOCKER:-unset} TZ=${TZ:-unset}"; locale; } | tee "$OUT/env-identity.txt" | tee -a "$L"
# 4. integration: append only the gem line, stage the built gem, keep every stage
cp Gemfile "$OUT/deps/1-Gemfile.original"; cp Gemfile.lock "$OUT/deps/1-Gemfile.lock.original"
printf '\n# saboteur field-run integration (gem built from the pinned source, not the registry)\ngem "saboteur", "0.12.3", group: :test\n' >> Gemfile
mkdir -p vendor/cache; cp /tmp/gem-build/saboteur-0.12.3.gem vendor/cache/   # the only saboteur artifact allowed in the cache
cp "$RECIPE_DIR/config.saboteur.rb" config/saboteur.rb
cp Gemfile "$OUT/deps/2-Gemfile.patched"; cp Gemfile.lock "$OUT/deps/2-Gemfile.lock.patched-preinstall"; cp config/saboteur.rb "$OUT/deps/config.saboteur.rb"
# No registry resolution may supply saboteur: fetch every ORDINARY locked gem by its exact lock string, then install --local from a
# complete cache that holds only the locally built saboteur artifact for that name.
grep -qE '^(GIT|PATH)$' Gemfile.lock && { echo "PREP_BLOCK: lock has GIT/PATH sources; the cache route does not cover them" | tee -a "$L"; exit 1; }
sed -n '/^GEM$/,/^PLATFORMS$/p' "$OUT/deps/1-Gemfile.lock.original" | grep -E '^    [A-Za-z0-9_.-]+ \([^)]+\)$' | sed -E 's/^    ([^ ]+) \(([^)]+)\)$/\1-\2/' | sort -u > "$OUT/deps/locked-gem-files.txt"
echo "LOCKED_GEMS $(wc -l < "$OUT/deps/locked-gem-files.txt")" | tee -a "$L"
! grep -q '^saboteur-' "$OUT/deps/locked-gem-files.txt" || { echo "PREP_BLOCK: original lock already names saboteur" | tee -a "$L"; exit 1; }
fetch_one() { f=$1; [ -s "vendor/cache/$f.gem" ] || curl -fsS --retry 4 --retry-delay 3 -o "vendor/cache/$f.gem" "https://rubygems.org/downloads/$f.gem"; }
export -f fetch_one
rc=0; capped 1800 bash -c 'xargs -a "$0" -P 4 -I{} bash -c "fetch_one {}"' "$OUT/deps/locked-gem-files.txt" > "$OUT/gem-fetch.log" 2>&1 || rc=$?
[ "$rc" = 0 ] || { echo "PREP_BLOCK: fetching locked gems failed (exit $rc, gem-fetch.log)" | tee -a "$L"; exit 1; }
( cd vendor/cache && sha256sum *.gem ) > "$OUT/deps/cache-sha256.txt"
echo "CACHE_GEMS $(ls vendor/cache/*.gem | wc -l) (locked + 1 built saboteur)" | tee -a "$L"
rc=0; capped 3000 bundle install --local --jobs 1 > "$OUT/bundle-install.log" 2>&1 || rc=$?
tail -3 "$OUT/bundle-install.log" | tee -a "$L"
[ "$rc" = 0 ] || { echo "PREP_BLOCK: bundle install exit $rc" | tee -a "$L"; exit 1; }
cp Gemfile.lock "$OUT/deps/3-Gemfile.lock.installed"
# the ONLY allowed change to the original lock is the approved saboteur instrumentation addition (exact lines, prism already locked)
diff "$OUT/deps/1-Gemfile.lock.original" "$OUT/deps/3-Gemfile.lock.installed" > "$OUT/deps/lock-additions-vs-original.diff" || true
mapfile -t GEMDEPS < <(capped 120 ruby -rrubygems/package -e 'Gem::Package.new(ARGV[0]).spec.runtime_dependencies.each { |d| puts "#{d.name} (#{d.requirement})" }' /tmp/gem-build/saboteur-0.12.3.gem)
printf 'BUILT_GEM_RUNTIME_DEPENDENCIES %s\n' "${GEMDEPS[@]}" | tee -a "$L"
[ "${#GEMDEPS[@]}" -ge 1 ] || { echo "PREP_BLOCK: could not read the built gem's dependencies" | tee -a "$L"; exit 1; }
python3 "$RECIPE_DIR/lockgate_add.py" "$OUT/deps/1-Gemfile.lock.original" "$OUT/deps/3-Gemfile.lock.installed" "${GEMDEPS[@]}" | tee -a "$L" || { echo "PREP_BLOCK: lock differs from the original beyond the approved saboteur addition" | tee -a "$L"; exit 1; }
bundle list > "$OUT/deps/bundle-list.txt" 2>&1
inst=$(capped 300 bundle exec ruby -e 'puts Gem.loaded_specs["saboteur"].full_gem_path')
for d in lib exe; do
  [ -d "/tmp/gem-b/saboteur-0.12.3/$d" ] || continue
  rc=0; diff -r "/tmp/gem-b/saboteur-0.12.3/$d" "$inst/$d" > "$OUT/deps/installed-$d-diff.txt" || rc=$?
  [ "$rc" = 0 ] || { echo "PREP_BLOCK: installed saboteur $d differs from the built payload" | tee -a "$L"; exit 1; }
  echo "INSTALLED_${d}_IDENTICAL $inst/$d" | tee -a "$L"
done
# 5. effective config gate and expected map identity, from the pinned tool's own constants
capped 300 bundle exec ruby -rjson -rdigest -e '
require "saboteur"
c = Saboteur::Config.load(root: Dir.pwd, path: nil, overrides: {})
six = Saboteur::Engine::CoverageStore::CACHE_INPUTS.to_h { |k| [k, c[k]] }
puts "EFFECTIVE " + JSON.generate(six) + " include=" + JSON.generate(c["include"]) + " jobs=#{c["jobs"]} baseline_timeout=#{c["baseline_timeout"]} partial_coverage=#{c["partial_coverage"]} cache=#{c["cache"]} seed=#{c["seed"]}"
abort("effective config mismatch") unless c["include"] == ["app/**/*.rb", "lib/**/*.rb"] && c["jobs"] == 1 && c["baseline_timeout"] == 3600 && c["partial_coverage"] == "off" && c["cache"] == true && c["seed"] == 1 && c["rails"] == true && c["require"] == ["./config/environment"]
File.write(ARGV[0], JSON.generate(root_path: Dir.pwd, root: Digest::SHA256.hexdigest(Dir.pwd),
  settings: Digest::SHA256.hexdigest(JSON.generate(six)), runtime: Saboteur::Engine::CoverageInputsSnapshot.runtime_digest))' "$OUT/deps/expected-identity.json" | tee -a "$L"
tee -a "$L" < "$OUT/deps/expected-identity.json"; echo | tee -a "$L"
# 6. receipts: hashes of what this run used
{ echo "GEMFILE_LOCK_ORIGINAL sha256=$(sha256sum "$OUT/deps/1-Gemfile.lock.original" | cut -d' ' -f1)"
  echo "GEMFILE_LOCK_INSTALLED sha256=$(sha256sum Gemfile.lock | cut -d' ' -f1)"
  echo "CONFIG sha256=$(sha256sum config/saboteur.rb | cut -d' ' -f1)"
  for f in config/saboteur_custom_map.rb config/saboteur_ignore.rb; do [ -e "$f" ] && echo "PRESENT $f sha256=$(sha256sum "$f" | cut -d' ' -f1)" || echo "ABSENT $f"; done
  echo "SABOTEUR_BIN $(capped 300 bundle exec saboteur version)"; } | tee "$OUT/RECEIPTS.txt" | tee -a "$L"
stamp "PREP_DONE" | tee -a "$L"
