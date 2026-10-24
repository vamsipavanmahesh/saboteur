#!/bin/bash
# EXACT procedure used to produce the Ruby runtime for this field run (see ENV.md deviation note).
# Source tarball: https://github.com/ruby/ruby-builder/releases/download/toolcache/ruby-3.4.6-ubuntu-22.04.tar.gz
# Built for prefix /opt/hostedtoolcache/Ruby/3.4.6/x64; relocated to /home/sandbox/ruby34cache/3.4.6/x64
# using an EQUAL-LENGTH (35-byte) replacement so no binary offsets change.
set -e
OLDSTR=/opt/hostedtoolcache/Ruby/3.4.6/x64
NEW=/home/sandbox/ruby34cache/3.4.6
NEWSTR=$NEW/x64
curl -sL -o ruby.tar.gz https://github.com/ruby/ruby-builder/releases/download/toolcache/ruby-3.4.6-ubuntu-22.04.tar.gz
mkdir -p $NEW && tar -xzf ruby.tar.gz -C $NEW
# 1) text files only (grep -I skips binaries): bin shebangs, rbconfig.rb, pkgconfig
grep -rIl "$OLDSTR" $NEWSTR/bin $NEWSTR/lib | while read f; do sed -i "s|$OLDSTR|$NEWSTR|g" "$f"; done
# 2) binaries: in-place equal-length prefix replacement
python3 - <<PY
old = b"$OLDSTR"; new = b"$NEWSTR"; assert len(old) == len(new) == 35
for path in ["$NEWSTR/bin/ruby", "$NEWSTR/lib/libruby.so.3.4.6"]:
    data = open(path, "rb").read()
    n = data.count(old); assert n >= 1
    open(path, "wb").write(data.replace(old, new))
PY
# user-space libyaml (psych native ext) - Ubuntu 22.04 debs extracted without root:
cd /tmp && apt-get download libyaml-0-2 libyaml-dev
for d in libyaml*.deb; do dpkg -x "$d" ~/sysroot; done
sed -i 's|^prefix=/usr$|prefix=/home/sandbox/sysroot/usr|' ~/sysroot/usr/lib/x86_64-linux-gnu/pkgconfig/yaml-0.1.pc
# env (field/env.sh):
#   PATH=$NEWSTR/bin:$PATH
#   PKG_CONFIG_PATH=$HOME/sysroot/usr/lib/x86_64-linux-gnu/pkgconfig
#   LD_LIBRARY_PATH=$HOME/sysroot/usr/lib/x86_64-linux-gnu
