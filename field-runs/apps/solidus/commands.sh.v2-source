#!/bin/bash
# Exact commands executed for the Solidus field run. Environment first:
#   source /home/sandbox/field/env.sh   # PATH to relocated ruby 3.4.6, PKG_CONFIG_PATH+LD_LIBRARY_PATH for user-space libyaml
set -x
git clone https://github.com/solidusio/solidus repo && cd repo && git checkout 07d5aff446586f6ab8ca024e2d8d08ee3e0463d8
bundle install   # log: logs/env-bundle-install.log (first attempt failed on psych 5.5.0, missing libyaml; succeeded after user-space libyaml; rerun on corrected runtime)
cd core
bundle exec rspec spec/lib/spree/core/version_spec.rb --format doc   # smoke 1 (no rails boot)
bundle exec rspec spec/models/spree/address_spec.rb --format doc     # smoke 2 (DummyApp boot + auto_migrate + sqlite)
bundle exec rspec --format progress --format json --out /home/sandbox/field/runs/apps/solidus/logs/baseline-rspec.json   # BASELINE (README command; json formatter added for evidence)
bundle exec rspec spec/models/spree/image_spec.rb spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb   # failure recheck run A (default vips): 19 examples, 8 failures
ACTIVE_STORAGE_VARIANT_PROCESSOR=mini_magick bundle exec rspec spec/models/spree/image_spec.rb spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb   # recheck run B: 19 examples, 6 failures (saver unsupported)
