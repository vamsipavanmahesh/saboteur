# Ruby 4.0.0 (lobsters pins it) with no rvm gem paths; bundle in BENCH_TARGETS.
RUBY_CMD=(env -u GEM_HOME -u GEM_PATH -u RUBYOPT -u RUBYLIB -u BUNDLE_BIN_PATH
          PATH="$HOME/.rubies/ruby-4.0.0/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
          RAILS_ENV=test BUNDLE_GEMFILE=Gemfile.bench BUNDLE_PATH="$BENCH_TARGETS/lobsters-bundle")
RAILS=true
