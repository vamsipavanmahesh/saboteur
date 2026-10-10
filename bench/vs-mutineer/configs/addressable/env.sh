# Ruby and bundle for addressable (sourced by run_one).
RUBY_CMD=(rvm 3.4.3 do env BUNDLE_GEMFILE=Gemfile.bench BUNDLE_PATH="$BENCH_TARGETS/addressable-bundle" IDNA_MODE=pure)
RAILS=false
