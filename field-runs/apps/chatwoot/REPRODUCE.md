# Chatwoot evidence replay notes

Raw successful-run helpers are in helpers/run-baseline.sh and helpers/run-baseline-extra.sh. They assume the historical working directory $HOME/fieldruns/chatwoot-git and evidence root $HOME/fieldruns/evidence/apps/chatwoot. helpers/env.sh configures the locally built toolchain. Before replay, create the historical evidence directories and copy helpers/env.sh to $HOME/fieldruns/env.sh, or explicitly change and record these paths for a new run. Do not overwrite preserved original evidence.

helpers/provision.sh and commands.sh are grouped provisioning recipes, not a literal complete attempt transcript. commands.sh.source preserves the supplied source text. The source-build recipe and published helper packaging have not been rerun from this evidence directory. Ensure $HOME/local/lib exists before the provisioner's symlink step. Generate local test keys from the public-safe template; no saved private application keys are included. Record any changes and new outputs rather than silently replacing originals.

The baseline scripts do not reliably propagate a failed RSpec exit as their own shell exit because they end with echo. Their recorded exit_code in meta.env and the RSpec JSON/log are the evidence for the actual command outcome; wrapper success alone is not enough. Do not use these wrappers' final shell status as a CI gate without a separately reviewed change.

Timing uses integer date timestamps and a polling loop, not a monotonic high-resolution process-only clock. Memory uses ps -o rss --ppid <rspec_pid> -p <rspec_pid>, so only the parent and direct children are sampled. The raw metadata's phrase 'process tree' is broader than the command supports. Peak RSS remains the original observed value; no correction or implied total is invented.

All path references beginning apps/chatwoot/ are relative to the field-runs/ evidence root. The source MANIFEST includes a self-checksum that does not match itself; every non-manifest file matched at receipt. MANIFEST-source.sha256 preserves that source file, not a claim that the self-row validates.
