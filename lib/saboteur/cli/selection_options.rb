# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # The run's subject-selection flags: operator sets, single-mutant replay,
    # --since scoping, --dry-run, the flaky-check confirmation rerun (#476)
    # and explicit --subject filters. Grouped so the CLI stays under the
    # house size caps.
    module SelectionOptions
      private

      def define_selection_options(opts)
        opts.on("--operators NAMES", Array, "Choose operator names (default: all)") do |v|
          set(:operators, v)
        end
        opts.on("--exclude-operators NAMES", Array, "Exclude operator names from the selected set") do |v|
          set(:exclude_operators, v)
        end
        opts.on("--list-operators", "List operator names and descriptions") { set(:list_operators, true) }
        opts.on("--dry-run", "Preview mutants without boot, tests, forks or report writes") { set(:dry_run, true) }
        opts.on("--id DIGEST", "Replay exactly one current mutant by its full digest") { |v| set(:id, v) }
        opts.on("--shard K/N", "Run one of N deterministic candidate shards (for example 1/4)") { |v| set(:shard, v) }
        opts.on("--since REF", "Only mutate subjects changed since git REF") { |v| options[:since] = v }
        opts.on("--ignore-empty", "A --since diff that selects no mutants exits 0 with a note instead of " \
                                  "failing a score gate") { set(:ignore_empty, true) }
        flaky_desc = "Confirm a fresh verdict (survivors, decisive) with one reordered rerun"
        opts.on("--flaky-check MODE", %w[off survivors decisive], flaky_desc) { |v| set(:flaky_check, v) }
        opts.on("--subject EXPR", "Klass#meth, Klass.meth or a namespace; repeatable") { |v| add_subject(v) }
      end
    end
  end
end
