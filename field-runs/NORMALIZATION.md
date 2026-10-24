# Evidence normalization for publication

The repository diff-check gate (`git diff --check`) rejects trailing blank
lines at end of file and trailing whitespace. 26 raw RSpec/tool logs and
REPORT.md in this evidence set contained exactly two such blemishes:

- trailing blank line(s) at end of file (25 files)
- four RSpec comment lines containing exactly `# ` (hash + trailing space):
  apps/chatwoot/logs/pr-checks/15807-base-rspec.log:36,
  apps/chatwoot/logs/pr-checks/16253-base-rspec.log:36,
  apps/lobsters/logs/pr-bases-driver.log:150,
  apps/lobsters/logs/pr2156-base-specs.log:70

The published text files are whitespace-normalized views: trailing blank
lines at EOF were removed and those four lines were reduced to `#`. No
other byte changed. No numeric or prose content changed. These views are
NOT byte-identical to the captured originals and are not represented as
such. REPORT.md's only change is removal of the final blank line;
REPORT.html and REPORT.pdf are byte-unchanged.

The exact original bytes are preserved alongside each view as
<name>.gz (deterministic gzip, `gzip -9 -n`; `gunzip -c <name>.gz`
reproduces the original). The table below maps every view to its original
sha256; the original hashes also match the pre-normalization
MANIFEST.sha256 entries at commit a8514100. apps/chatwoot/MANIFEST-source.sha256
and MANIFEST-source-2221.sha256 are source-stage seals: their log hashes
describe the captured originals (i.e. the .gz contents), not the normalized
views. MANIFEST-source.sha256 already did not cover the composed top-level
MANIFEST.sha256 before this change (its ./MANIFEST.sha256 entry is the
empty-file hash placeholder e3b0c442...), so it was never a live-tree check.

| file | original sha256 (gunzip -c <file>.gz) | normalized view sha256 |
| --- | --- | --- |
| REPORT.md | 7ecb8e70da06eb463ddc6b98adbab2570843d9537550e6e6fbb8382fde51f9e5 | b9c6af09880790cd61d3b36d6b6bae652f64a55070f1655a60f472c28da45be4 |
| apps/chatwoot/logs/baseline-extra-rspec.log | 743d84e52a49fe1bb27d3c66541b98a9cdf863be1389e7ecdefa883e4409b32b | 8518dc91df1e545b66f49ef674c7b77039d4a501c0382fe76bbb5d62df2c0e03 |
| apps/chatwoot/logs/baseline-rspec.log | 36dd0445eb205fa6fb2637f0bc0bdd973faf0febf85b1d2887949416d15903a3 | 8244d65f2c1d68987bbe01cbc00efe80550fe7df840b3e0fd0ac0fe94f7df54b |
| apps/chatwoot/logs/pr-checks/15807-base-rspec.log | 478a5b7a684b409fc573cca22a0f5e240bbefefb91b427b5958caed13ec222a8 | 43a4b848054b0b49c45103cbfb1f89b718a48f00683b0cdcd026f5d0c656b38f |
| apps/chatwoot/logs/pr-checks/15807-head-rspec.log | 86906ef804b6c855c38f06826bfd2b8856b1c993ff6dda2d843c2f08de8abb47 | 91057b0a02eebe603a1bdde960becb9d37e9e64804b8723e639273a1c27441bc |
| apps/chatwoot/logs/pr-checks/15978-base-rspec.log | a0ffee962396f014d384e9411ecdd1e23b0826fe09030959d9cf6bc202825765 | b02012e36f48ccdc50810f4f8f28d1e6a20fb13314b31a411f3f84772bf6db26 |
| apps/chatwoot/logs/pr-checks/15978-head-rspec.log | 64323a174b3bf64447ff3dcdc0734fac26f94e39fb5ccccbf331a036a1f5bf90 | 641ebe7d29bbcddcda91b1f6258b80d3761748be6bf9457818de31740f4455dc |
| apps/chatwoot/logs/pr-checks/16182-base-rspec.log | cc32746f21faab97594170d5b5293a3517cc04a2e4c66ca1f14d74185b49a846 | 392cbae48c4ba122c472285c3b113b28fd52c9d0887adeda34dd3d223e542825 |
| apps/chatwoot/logs/pr-checks/16182-head-rspec.log | be36eb5e64519ef02eeb0a5f15e536bfefec138d6313c93575ce6a82912f6de6 | 6f53f29b9fa590717c18451b2da5690fcdece2180e3e0c9c838948b496b73a57 |
| apps/chatwoot/logs/pr-checks/16185-base-rspec.log | b6c1964fe57ef68347549d67ceca0e4fe2c7973ca3e8c3b5c1b95d4fcade1329 | 22493e8a851525e4057a64c5afb902bd109e56e8dd069b92ab2eb05ce765c9c1 |
| apps/chatwoot/logs/pr-checks/16185-head-rspec.log | bd793ed59b7c903591c67978a6a92ecd55927461649f383ad387bfcf921083aa | 2519e08cc783b7d71a0db431bc459b33323edd9f7f59556e3b2d4429943c8daa |
| apps/chatwoot/logs/pr-checks/16253-base-rspec.log | 2dae22ef16c22069bb807fa3193c346f7d1c0d334cbec2aef5d65b2cbf619ecb | 550db084b16210222f6b08b13969df5d3f88945bb755bc043efe789a70343e2c |
| apps/chatwoot/logs/pr-checks/16253-head-rspec.log | f8ecaffc71bdd248d6d4c43ddabcbe229ce0f7ff02787586f0e400fb0f2038b0 | 0cfd67a4362d7bedd25ef7dd4075f8948b3009f5aab0583e11a80ed5b0a76a19 |
| apps/lobsters/logs/pr-bases-driver.log | d2afed091f25984de921d5c926a5b3b756538ab5fbf6de08b7a499df3e38aadd | 7087827e91327f8d4ac07c15557df4011d9c389596bd5581890214102169ed8c |
| apps/lobsters/logs/pr2156-base-specs.log | 987aa6f33cd02114be9f2a58784937308d12d2c92cfb6d0ef432ac37f5ff1255 | d231203bd60b85d2aca6f5be98298134a565b9179691ff357b7ce3e413d4f0e1 |
| apps/solidus/logs/env-smoke.log | 9bd5c29aa7546445cc7c675ec1328ec0fcb52449c4b29cba4f07e3a7af9a6cc5 | 6cd2e282d4ffea20dd3d6cc1d9492f5b6d850f005b97817aab3e65cf7ef3df03 |
| apps/solidus/reports/baseline/stdout+stderr.log | cebf3d0c6a57c97f050a20a2566f82a6e531a8d0f508f8dc996b9f2b01c6757b | e1da5fb32b15e74abd39d1a273eac3dc5b4c44e373e53ff0d5436716913e5c30 |
| apps/solidus/reports/pr6677-base-scope/stdout+stderr.log | 4e74766dbbb9930de146bb9405331292760976fb2d6dafecbff8f8361cf0d023 | cdd59e4f250f7949fb2bb03695eee68692ef810e402eb9ab08250c496774ebcf |
| apps/solidus/reports/pr6677-head-scope/stdout+stderr.log | b96cbfaadcc6c712f5a151eaf714f2103a84adf62d12c184b50a0f4521300c71 | a3c4c14d592a397fa1c24f4eaaaf383201085b165afb39dcda8fe27f1496f0bf |
| apps/solidus/reports/pr6691-base-scope/stdout+stderr.log | 5ca1cf1b6e82d1ea5d785827ff43123001499d4761cfb3bc937bb64ee8851c2d | 3c24210201a30d9a9bc874530f160509dd6467f189099729af408e8aefbaf7d4 |
| apps/solidus/reports/pr6691-head-scope/stdout+stderr.log | 930a5c8c2bd8ac1355d7d7cd64c9d2802145ce3367509195044870de5a8dc0bb | 1ff4c8f33435e1b06915ebb0614fd9ae07a384c56dbf598ed25493ae4f81f917 |
| apps/solidus/reports/pr6692-base-scope/stdout+stderr.log | 0a6fcb8c1eadf277e879d5f44415ab374af04109907e00e161db18ef0c772ee1 | d1f61f2263d371651763d41d53805b8e6633884c4d83bb72603c7825343537f4 |
| apps/solidus/reports/pr6692-head-scope/stdout+stderr.log | c83aed983a67f9dd793d0ccbcde18efc3f94f8a09a024776a4eb366fd7cd3382 | ace9082af67c104a26ed551f798a0af74df90e36f6aa7a696deb5aaf09d73140 |
| apps/solidus/reports/pr6697-base-scope/stdout+stderr.log | ff4d50e238293193ec25ff29636761ce1269fac782a47ac493e8a529b61f4ec0 | 8f13967d9bf0899640ea1efe47a210a17a3da3feb97a23a20606305530e53b9d |
| apps/solidus/reports/pr6697-head-scope/stdout+stderr.log | 5c85d03bf0f6c1d4c1038741711ae7394488e8dd52bf3703455c00966c4883a8 | 47f69e654e4b8d86d241d696a6fc8b59a3f7f0cdde39500a89396e98076de99a |
| apps/solidus/reports/pr6701-base-scope/stdout+stderr.log | 3a581b3b3615cf38ffe78d7987057447372b7eab66a7f19e3e28a971cf7bef45 | 103b6116cb3d50b57c7ca1da00f440a3e621c00db34573fcdd9302c9d653fde9 |
| apps/solidus/reports/pr6701-head-scope/stdout+stderr.log | 50dc1284548e1744844c692131154f67c3551ace2558cdca066f29062c59dd6e | 2c0b5453e74d751d6a4fede7f7b06435037ef9019aadcae3a2494a94e6222b95 |
