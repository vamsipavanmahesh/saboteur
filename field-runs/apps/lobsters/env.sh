# Lobsters field-run environment - source this in every shell
export FIELD_RUNS=~/field-runs
export RUBY_HOME=$FIELD_RUNS/ruby/ruby-4.0.9
export VIPS_ROOT=$FIELD_RUNS/pkgs/root/usr/lib/x86_64-linux-gnu
export LD_LIBRARY_PATH=$RUBY_HOME/lib:$FIELD_RUNS/pkgs/vips818/lib:$VIPS_ROOT
export RUBYLIB=$RUBY_HOME/lib/ruby/4.0.0:$RUBY_HOME/lib/ruby/4.0.0/x86_64-linux:$RUBY_HOME/lib/ruby/site_ruby/4.0.0:$RUBY_HOME/lib/ruby/site_ruby/4.0.0/x86_64-linux:$RUBY_HOME/lib/ruby/vendor_ruby/4.0.0:$RUBY_HOME/lib/ruby/vendor_ruby/4.0.0/x86_64-linux
export GEM_HOME=$RUBY_HOME/lib/ruby/gems/4.0.0
export GEM_PATH=$GEM_HOME
export PATH=$RUBY_HOME/bin:$GEM_HOME/bin:/usr/local/bin:/usr/bin:/bin
export LOBSTERS_DIR=$FIELD_RUNS/lobsters
export EVIDENCE_DIR=$FIELD_RUNS/saboteur-field-runs/apps/lobsters
export PKG_CONFIG_PATH=$FIELD_RUNS/pkgs/root/usr/lib/x86_64-linux-gnu/pkgconfig
export CPATH=$FIELD_RUNS/pkgs/root/usr/include
export LIBRARY_PATH=$FIELD_RUNS/pkgs/root/usr/lib/x86_64-linux-gnu
