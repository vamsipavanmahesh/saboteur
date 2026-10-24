export KILL_ROOT=/tmp/kill2231
export RUBY_HOME=$KILL_ROOT/runtime/x64
export PATH=$RUBY_HOME/bin:$PATH
export LD_LIBRARY_PATH=$RUBY_HOME/lib:$KILL_ROOT/pkgs/root/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}
export RUBYLIB=$RUBY_HOME/lib/ruby/4.0.0:$RUBY_HOME/lib/ruby/4.0.0/x86_64-linux:$RUBY_HOME/lib/ruby/site_ruby/4.0.0:$RUBY_HOME/lib/ruby/site_ruby/4.0.0/x86_64-linux
export GEM_HOME=$KILL_ROOT/gems
export GEM_PATH=$GEM_HOME:$RUBY_HOME/lib/ruby/gems/4.0.0
export PKG_CONFIG_PATH=$KILL_ROOT/pkgs/root/usr/lib/x86_64-linux-gnu/pkgconfig
export CPATH=$KILL_ROOT/pkgs/root/usr/include
export LIBRARY_PATH=$KILL_ROOT/pkgs/root/usr/lib/x86_64-linux-gnu

export LD_LIBRARY_PATH=/tmp/kill2231/pkgs/vips/package/lib:$LD_LIBRARY_PATH
