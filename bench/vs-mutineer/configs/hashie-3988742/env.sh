# Ruby and bundle for hashie (sourced by run_one).
RUBY_CMD=(rvm 3.4.3 do env BUNDLE_GEMFILE=Gemfile.bench BUNDLE_PATH="$BENCH_TARGETS/hashie-bundle" IDNA_MODE=pure)
RAILS=false
