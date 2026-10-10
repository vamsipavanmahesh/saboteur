# Ruby 3.4.3. BENCH_HE_ENV names a mode-600 file with RAILS_ENV and the test
# DATABASE_URL (Postgres in Docker); it is sourced, never printed.
. "${BENCH_HE_ENV:?set BENCH_HE_ENV}"
RUBY_CMD=(rvm 3.4.3 do env BUNDLE_GEMFILE="$BENCH_TARGETS/human-essentials-bench/Gemfile")
RAILS=true
# mutineer only: forking after boot crashes on macOS (Objective-C fork-safety
# abort, 428 times in the smoke run). These are the user-level workarounds;
# saboteur sets PGGSSENCMODE itself. Recorded as a mutineer workaround.
if [ "${tool:-}" = mutineer ] && [ "${BENCH_MUTINEER_NO_WORKAROUND:-0}" != 1 ]; then
  RUBY_CMD+=(OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES PGGSSENCMODE=disable)
fi
