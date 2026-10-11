# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Research spike: can a comparison of compiled CRuby instruction sequences
# indicate that a mutant behaves like its original? Nothing here is wired
# into the saboteur engine.
require_relative "trivial_equivalence/compiler_pin"
require_relative "trivial_equivalence/instruction_sequence_fingerprint"
require_relative "trivial_equivalence/reflection_scan"
require_relative "trivial_equivalence/verdict"
require_relative "trivial_equivalence/equivalence_judge"
