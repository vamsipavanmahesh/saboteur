# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module LocaleHelpers
  # Subprocess output and File.read results are tagged with
  # Encoding.default_external, so forcing it simulates a non-UTF-8 locale
  # (LANG=C) without forking a new process.
  def with_default_external(encoding)
    previous = Encoding.default_external
    verbose = $VERBOSE
    $VERBOSE = nil
    Encoding.default_external = encoding
    yield
  ensure
    Encoding.default_external = previous
    $VERBOSE = verbose
  end
end

RSpec.configure { |config| config.include LocaleHelpers }
