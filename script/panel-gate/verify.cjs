// SPDX-License-Identifier: MIT
'use strict';
const fs = require('node:fs');
const policy = require('./policy.json');
const SHA = /^[0-9a-f]{40}$/;
const keys = ['schema', 'lens', 'head', 'verdict', 'scope', 'independently_run',
  'author_reported', 'uncertainty', 'prior_findings', 'blockers', 'human_approval'];
function demand(ok, message) { if (!ok) throw new Error(message); }
// Revocation records name lenses from the live policy, never a hardcoded set.
const LENSES = Object.keys(policy.reviewers).join('|');
function parse(body) {
  // One canonical block at the start. Never scrape APPROVE from prose/quotes.
  const match = /^```panel-verdict\n([^]*?)\n```(?:\n|$)/.exec(body || '');
  demand(match && !body.slice(match[0].length).includes('```panel-verdict'), 'missing/duplicate marker');
  const value = JSON.parse(match[1]);
  demand(value && typeof value === 'object' && !Array.isArray(value), 'marker must be object');
  demand(Object.keys(value).sort().join() === keys.slice().sort().join(), 'unexpected/missing fields');
  // JSON duplicates are ambiguous. Canonical JSON is required, not repaired.
  demand(JSON.stringify(value, null, 2) === match[1], 'noncanonical JSON');
  demand(value.schema === 1 && Object.hasOwn(policy.reviewers, value.lens), 'schema/lens');
  demand(SHA.test(value.head) && typeof value.head === 'string', 'full lowercase head SHA required');
  // CHANGES_REQUESTED is the GitHub review-state spelling; it is the same
  // verdict, so a superseded marker in that spelling cannot poison a PR
  // whose newer markers are valid (#278). Normalize before the demands.
  if (value.verdict === 'CHANGES_REQUESTED') value.verdict = 'CHANGES_REQUIRED';
  demand(['APPROVE', 'CHANGES_REQUIRED'].includes(value.verdict), 'verdict');
  // An APPROVE marker binds the human's decision to the exact head it covers.
  // The publisher id is shared between the user and his agents, so the marker
  // cannot prove who clicked approve; it records the binding and the
  // maintainer holds the private-channel evidence. The gate enforces the
  // binding mechanically (exact head, non-empty note) and states the human
  // origin as procedure, never as cryptographic proof.
  if (value.verdict === 'APPROVE') {
    const approval = value.human_approval;
    demand(approval && typeof approval === 'object' && !Array.isArray(approval) &&
      approval.head === value.head && typeof approval.note === 'string' && approval.note.trim().length > 0,
      'approval must bind the human decision to the exact head');
  } else {
    demand(value.human_approval === null, 'changes-requested marker carries no human approval');
  }
  demand(typeof value.scope === 'string' && value.scope.trim().length > 0, 'scope required');
  for (const field of ['independently_run', 'author_reported', 'uncertainty', 'prior_findings', 'blockers']) {
    demand(Array.isArray(value[field]) && value[field].every(x => typeof x === 'string' && x.trim()), `${field} must be string array`);
  }
  demand(value.verdict !== 'APPROVE' || value.blockers.length === 0, 'approval with blockers');
  demand(value.verdict !== 'CHANGES_REQUIRED' || value.blockers.length > 0, 'changes requires blockers');
  return value;
}
function panel(comments, head, revoked = {}) {
  const latest = new Map();
  for (const comment of comments.slice().sort((a, b) => (Date.parse(a.updated_at) || a.id) - (Date.parse(b.updated_at) || b.id) || a.id - b.id)) {
    const trusted = Object.values(policy.reviewers).some(ids => ids.includes(comment.user?.id));
    if (!trusted) continue;
    // Trusted malformed markers fail closed, including markers in quoted text.
    if (!comment.body?.includes('```panel-verdict')) continue;
    const marker = parse(comment.body);
    demand(policy.reviewers[marker.lens].includes(comment.user.id), 'wrong publisher for lens');
    // Latest comment per lens wins even if it points to an older head.
    latest.set(marker.lens, {...marker, commentId: comment.id, createdAt: Date.parse(comment.created_at)});
  }
  for (const lens of Object.keys(policy.reviewers)) {
    const verdict = latest.get(lens);
    const cutoff = revoked[lens];
    demand(verdict?.head === head && verdict.verdict === 'APPROVE' &&
      (!cutoff || (verdict.commentId > cutoff.id && verdict.createdAt > cutoff.epoch)),
    `${lens}: missing, stale, revoked or blocking verdict`);
  }
  return Object.fromEntries(latest);
}
function jobsPass(jobs, names, head) {
  // Named jobs are aggregate checks that own exhaustiveness themselves:
  // ci-passed needs every other ci.yml job and fails on any failure or
  // unexpected skip, so the gate demands each named job green on the exact
  // head and treats every other job record as the aggregate's input, not as
  // a separate verdict. A missing or duplicated named job fails closed.
  for (const name of names) {
    const matches = jobs.filter(j => j.name === name);
    demand(matches.length === 1, `expected exactly one job named: ${name}`);
    const job = matches[0];
    demand(job.head_sha === head && job.status === 'completed' && job.conclusion === 'success', `job not green: ${name}`);
  }
}
// The trailing block of "Token: value" lines, matching git interpret-trailers:
// a sign-off outside it (subject line, mid-body, or a message with no subject
// paragraph before it) does not count.
function trailerBlock(message) {
  const lines = message.split(/\r?\n/);
  let i = lines.length;
  while (i > 0 && lines[i - 1] === '') i--;
  const block = [];
  while (i > 0 && /^[A-Za-z0-9-]+: /.test(lines[i - 1])) block.unshift(lines[--i]);
  // git requires a blank line before the block and a subject before that.
  if (i < 2 || lines[i - 1] !== '') return [];
  return block;
}
function dco(commits) {
  demand(commits.length > 0, 'empty commit range');
  for (const commit of commits) {
    if (commit.parents.length > 1) continue; // Existing project policy exempts merge commits.
    const author = commit.commit.author;
    demand(author?.name && author?.email, 'missing commit author');
    const line = `Signed-off-by: ${author.name} <${author.email}>`;
    demand(trailerBlock(commit.commit.message).includes(line), `missing author signoff trailer: ${commit.sha}`);
  }
}
// GitHub answers quota exhaustion with 403/429. It is reported on its own so the gate stops
// instead of spending more calls (even a failure status write) against a spent token.
class RateLimitError extends Error {
  constructor(message) { super(message); this.name = 'RateLimitError'; }
}
class API {
  constructor(repo, token) { this.repo = repo; this.token = token; }
  async call(path, method = 'GET', data) {
    const response = await fetch(`https://api.github.com/repos/${this.repo}/${path}`, {
      method, headers: {'Authorization': `Bearer ${this.token}`, 'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json'},
      ...(data ? {body: JSON.stringify(data)} : {})
    });
    if (!response.ok) {
      const header = name => response.headers?.get(name);
      const detail = await response.text().then(text => { try { return JSON.parse(text).message; } catch { return text; } }, () => '');
      // Only real exhaustion evidence counts: 429, no calls remaining, a retry-after header, or the
      // secondary-limit wording. A bare 403 (permissions, SSO) stays an ordinary failure, so the
      // gate still writes its fail-closed status.
      const exhausted = response.status === 429 || header('x-ratelimit-remaining') === '0' ||
        header('retry-after') != null || (response.status === 403 && /rate limit|abuse/i.test(String(detail)));
      if (exhausted) {
        const reset = Number(header('x-ratelimit-reset'));
        const resetAt = Number.isFinite(reset) && reset > 0 ? new Date(reset * 1000).toISOString() : 'unknown';
        throw new RateLimitError(`GitHub API ${response.status} (rate limit): ${path}; ` +
          `remaining ${header('x-ratelimit-remaining') ?? 'unknown'}, resets ${resetAt}; ` +
          `${String(detail || 'no message').slice(0, 200)}; stopped without writing statuses`);
      }
    }
    demand(response.ok, `GitHub API ${response.status}: ${path}`);
    return response.status === 204 ? null : response.json();
  }
  async pages(path, field) {
    const rows = [];
    for (let page = 1; page <= 100; page++) {
      const result = await this.call(`${path}${path.includes('?') ? '&' : '?'}per_page=100&page=${page}`);
      const part = field ? result[field] : result;
      demand(Array.isArray(part), 'unexpected API list');
      rows.push(...part);
      if (part.length < 100) return rows;
    }
    throw new Error('pagination limit reached');
  }
}
// Stable trusted-main anchor, scoped by PR, survives head pushes and stale-SHA markers.
const ledgerContext = number => `panel/revoked/pr-${number}`;
// A single intent covers all affected lenses before any fragile comments read.
// The redundant gate failure is also a durable latch, not a disposable display.
const intentContext = number => `panel/revocation-intent/pr-${number}`;
function intent(record, number) {
  const match = new RegExp(`^(all|${LENSES}):([1-9][0-9]*)$`).exec(record.description || '');
  const latch = new RegExp(`^revoked-pr-${number}:(all|${LENSES}):([1-9][0-9]*)$`).exec(record.description || '');
  if (record.context === intentContext(number)) { demand(match, 'invalid revocation intent'); return match; }
  if (record.context === policy.context && latch) return latch;
  // Recover failures emitted by the previous verifier before this latch format.
  if (record.context === policy.context && record.description === 'Verdict edited/deleted; require fresh panel attestations') {
    return [record.description, 'all', '1'];
  }
  return null;
}
// Fast-forward pushes retain old heads as PR commits. Force-pushes may abandon
// them, so every force-push creates a conservative all-lens freshness floor.
async function prRevocationSources(api, number, head) {
  const [commits, events] = await Promise.all([
    api.pages(`pulls/${number}/commits`), api.pages(`issues/${number}/events`)
  ]);
  const heads = [...new Set([head, ...commits.map(c => c.sha)])];
  demand(heads.every(sha => SHA.test(sha)), 'invalid recovery commit SHA');
  const records = (await Promise.all(heads.map(sha => api.pages(`commits/${sha}/statuses`)))).flat();
  let forceEpoch = 0;
  for (const event of events) {
    if (event.event !== 'head_ref_force_pushed') continue;
    const epoch = Date.parse(event.created_at);
    demand(Number.isFinite(epoch), 'invalid force-push event epoch');
    forceEpoch = Math.max(forceEpoch, epoch);
  }
  return {records, forceEpoch};
}
const readLedger = api => api.pages(`commits/${policy.revocationAnchor}/statuses`);
// `known` carries facts already read in this sweep: the shared anchor ledger and this PR's sources.
async function recoverRevocations(api, number, head, known = {}) {
  const [ledger, sources] = await Promise.all([
    known.ledger ?? readLedger(api), known.sources ?? prRevocationSources(api, number, head)
  ]);
  const records = sources.records;
  // Promote head-only latches before any pending/success can replace the display.
  // Preserve the original server epoch in the recovery record, not recovery time.
  for (const record of records) {
    const match = intent(record, number);
    if (!match) continue;
    const epoch = Date.parse(record.created_at);
    demand(Number.isFinite(epoch), 'invalid revocation latch epoch');
    const description = `${match[1]}:${match[2]}:${epoch}`;
    if (ledger.some(r => r.context === ledgerContext(number) && r.description === description)) continue;
    const saved = await api.call(`statuses/${policy.revocationAnchor}`, 'POST', {
      state: 'error', context: ledgerContext(number), description
    });
    // Local de-duplication only; API implementations may share the backing list.
    if (!ledger.some(r => r.context === ledgerContext(number) && r.description === description)) ledger.push(saved);
  }
}
async function revocations(api, number, head, known = {}) {
  const [ledger, sources] = await Promise.all([
    known.ledger ?? readLedger(api), known.sources ?? prRevocationSources(api, number, head)
  ]);
  const revoked = {};
  if (sources.forceEpoch) {
    for (const lens of Object.keys(policy.reviewers)) revoked[lens] = {id: 0, epoch: sources.forceEpoch};
  }
  for (const record of [...ledger, ...sources.records]) {
    const latch = intent(record, number);
    const relevant = record.context === ledgerContext(number) || record.context === 'panel/deleted-verdict';
    if (!latch && !relevant) continue;
    const match = latch || new RegExp(`^(all|${LENSES}):([1-9][0-9]*)(?::([0-9]+))?$`).exec(record.description || '');
    const epoch = match?.[3] ? Number(match[3]) : Date.parse(record.created_at);
    demand(match && Number.isSafeInteger(Number(match[2])) && Number.isFinite(epoch), 'invalid revocation record');
    const lenses = match[1] === 'all' ? Object.keys(policy.reviewers) : [match[1]];
    for (const lens of lenses) {
      const previous = revoked[lens];
      revoked[lens] = {id: Math.max(previous?.id || 0, Number(match[2])), epoch: Math.max(previous?.epoch || 0, epoch)};
    }
  }
  return Object.fromEntries(Object.keys(policy.reviewers).filter(lens => revoked[lens]).map(lens => [lens, revoked[lens]]));
}
async function revokeEvent(api, event) {
  if (!['edited', 'deleted'].includes(event.action) || !event.issue?.pull_request) return;
  const id = event.comment?.user?.id;
  const oldBody = event.action === 'edited' ? event.changes?.body?.from : event.comment?.body;
  if (!Object.values(policy.reviewers).some(ids => ids.includes(id)) || !oldBody?.includes('```panel-verdict')) return;
  let lens = 'all';
  try {
    const marker = parse(oldBody);
    demand(policy.reviewers[marker.lens].includes(id), 'revoked marker wrong publisher');
    lens = marker.lens;
  } catch { /* One atomic all-lens intent handles malformed trusted markers. */ }
  demand(Number.isSafeInteger(event.comment.id) && event.comment.id > 0 && SHA.test(policy.revocationAnchor), 'invalid revocation facts');
  const number = event.issue.number, description = `${lens}:${event.comment.id}`;
  const pr = await api.call(`pulls/${number}`);
  // Attempt BOTH independent latches even if one write fails. Both are consumed
  // by verification; head-only persistence is promoted to the stable anchor.
  const writes = await Promise.allSettled([
    api.call(`statuses/${policy.revocationAnchor}`, 'POST', {state: 'error', context: intentContext(number), description}),
    api.call(`statuses/${pr.head.sha}`, 'POST', {state: 'failure', context: policy.context,
      description: `revoked-pr-${number}:${description}`})
  ]);
  const rejected = writes.filter(w => w.status === 'rejected').map(w => w.reason);
  // A spent quota keeps its own error so the log shows the reset time; the latches were still attempted.
  const quota = rejected.find(reason => reason instanceof RateLimitError);
  if (quota) throw quota;
  if (rejected.length) throw new Error(`revocation latch write failed; retry event after API recovery: ${rejected.map(r => r?.message).join(' | ')}`);
  const comments = await api.pages(`issues/${number}/comments`);
  const highWater = Math.max(event.comment.id, ...comments.map(c => c.id));
  demand(Number.isSafeInteger(highWater) && highWater > 0, 'invalid comment high-water ID');
  // High-water refinement is optional for safety: the earlier server epoch
  // already excludes every approval created before the durable intent.
  await api.call(`statuses/${policy.revocationAnchor}`, 'POST', {
    state: 'error', context: ledgerContext(number), description: `${lens}:${highWater}`
  });
}
async function workflows(api, number, head) {
  // PR CI runs either on pull_request or, under manual CI, on a maintainer's
  // workflow_dispatch against the exact head; both prove the same head green.
  const runs = await api.pages(`actions/runs?head_sha=${head}`, 'workflow_runs');
  const checked = [];
  for (const [path, names] of Object.entries(policy.workflows)) {
    const matches = r => r.path === path && r.head_sha === head &&
      (r.event === 'pull_request' || r.event === 'workflow_dispatch') &&
      r.repository?.full_name === api.repo &&
      (r.pull_requests?.some(p => p.number === number) || r.event === 'workflow_dispatch');
    const run = runs.filter(matches).sort((a, b) => b.id - a.id)[0];
    demand(run, `missing current-head workflow: ${path}`);
    const fresh = await api.call(`actions/runs/${run.id}`);
    demand(fresh.id === run.id && matches(fresh) && Number.isSafeInteger(fresh.run_attempt) && fresh.run_attempt > 0 &&
      fresh.status === 'completed' && fresh.conclusion === 'success', `workflow not green: ${path}`);
    const jobs = await api.pages(`actions/runs/${run.id}/attempts/${fresh.run_attempt}/jobs`, 'jobs');
    jobsPass(jobs, names, head);
    checked.push({path, id: fresh.id, attempt: fresh.run_attempt, status: fresh.status, conclusion: fresh.conclusion,
      jobs: jobs.map(j => [j.id, j.name, j.head_sha, j.status, j.conclusion]).sort((a, b) => a[1].localeCompare(b[1]))});
  }
  return checked;
}
async function verify(api, number, sweep = {}) {
  const pr = await api.call(`pulls/${number}`);
  demand(pr.state === 'open' && !pr.draft && pr.base.ref === policy.baseBranch, 'not an open ready main PR');
  const head = pr.head.sha, base = pr.base.sha;
  demand(SHA.test(head) && SHA.test(base), 'bad PR SHA');
  const status = (state, description) => api.call(`statuses/${head}`, 'POST', {
    state, context: policy.context, description: description.slice(0, 140),
    target_url: `https://github.com/${api.repo}/actions/runs/${process.env.GITHUB_RUN_ID}`
  });
  try {
    // One read of the anchor ledger per sweep and one read of this PR's sources, shared by the
    // recovery and the first decision. The final re-check below always reads live.
    sweep.ledger ??= readLedger(api).catch(error => { delete sweep.ledger; throw error; });
    const known = {ledger: await sweep.ledger, sources: await prRevocationSources(api, number, head)};
    await recoverRevocations(api, number, head, known);
    await status('pending', 'Checking current head panel, CI, DCO and policy');
    // Up-to-date enforcement is intentionally relaxed: the head may trail main. Protected
    // files are compared against the merge base, so edits made on main are not blamed on the PR.
    const compare = await api.call(`compare/${base}...${head}`);
    demand(compare.status === 'ahead' || compare.status === 'diverged', 'head is not ahead of its base');
    const mergeBase = compare.merge_base_commit.sha;
    demand(SHA.test(mergeBase), 'bad merge base SHA');
    // Compare exact bytes via Git objects. Missing files on both sides are OK at bootstrap.
    // Protected paths may change in a pull request, but only with the owner's
    // approval marker on the exact head (the panel demand below); a pull
    // request that leaves them untouched needs no marker at all.
    const protectedChanged = [];
    for (const path of policy.protectedFiles) {
      async function blob(ref) {
        try { return await api.call(`contents/${path}?ref=${ref}`); }
        catch (error) { if (error.message.startsWith('GitHub API 404:')) return null; throw error; }
      }
      const [before, after] = await Promise.all([blob(mergeBase), blob(head)]);
      function identity(item) {
        if (Array.isArray(item)) return JSON.stringify(item.map(x => [x.name, x.sha, x.type]).sort());
        return item?.sha ?? null;
      }
      if (identity(before) !== identity(after)) protectedChanged.push(path);
    }
    const comments = await api.pages(`issues/${number}/comments`);
    const revoked = await revocations(api, number, head, known);
    if (protectedChanged.length > 0) panel(comments, head, revoked);
    dco(await api.pages(`pulls/${number}/commits`));
    const checkedRuns = await workflows(api, number, head);
    // Repeat the whole selection, latest attempt and job inspection, not just PR facts.
    // Recheck live facts immediately before publishing. New head never inherits success.
    const [lastPR, lastComments, lastRevoked, lastRuns] = await Promise.all([
      api.call(`pulls/${number}`), api.pages(`issues/${number}/comments`),
      revocations(api, number, head), workflows(api, number, head)
    ]);
    demand(JSON.stringify(lastRuns) === JSON.stringify(checkedRuns), 'CI runs/attempts/jobs changed during verification');
    demand(lastPR.state === 'open' && !lastPR.draft && lastPR.head.sha === head &&
      lastPR.base.ref === policy.baseBranch, 'PR changed during verification');
    demand(JSON.stringify(lastRevoked) === JSON.stringify(revoked), 'revocations changed during verification');
    if (protectedChanged.length > 0) panel(lastComments, head, lastRevoked);
    await status('success', protectedChanged.length > 0
      ? `user-approved protected change (${protectedChanged.length} path(s)) on the exact head; required checks green; DCO`
      : 'no protected paths changed; required checks green; DCO');
  } catch (error) {
    if (error instanceof RateLimitError) throw error;
    // A failed failure-write must not hide the reason the decision failed.
    try { await status('failure', error.message); } catch (writeError) {
      if (writeError instanceof RateLimitError) throw writeError;
      throw new Error(`${error.message} (and the failure status could not be written: ${writeError.message})`);
    }
    throw error;
  }
}
// Which open PRs an event can change. A comment, a dispatch and a CI run concern named PRs only;
// a push to main can change every PR's merge base, so it sweeps them all.
// Only a newer pending PUSH run proves it covers this run's targets: a push
// sweeps every open PR, while a comment, dispatch or CI-completion run is
// scoped to its own PRs by targets() and the shared queue hides which ones.
// Skipping on anything weaker loses verdicts for every intermediate PR in a
// mixed-PR backlog. Skipping the sweep lets a backed-up queue of push runs
// drain at seconds per stale run instead of a full sweep of every open PR
// per run against the token's rate budget. Only 'pending' is consulted:
// queue:max holds serialized runs in that state.
async function superseded(api) {
  const self = Number(process.env.GITHUB_RUN_ID);
  const file = (process.env.GITHUB_WORKFLOW_REF || '').split('@')[0].split('/').pop();
  demand(Number.isSafeInteger(self) && self > 0 && /\.ya?ml$/.test(file), 'invalid current run identity');
  const queued = await api.pages(`actions/workflows/${file}/runs?status=pending`, 'workflow_runs');
  return queued.some(run => run.id > self && run.event === 'push');
}
// Cross-lane serialization (#434): fork PRs run their CI-completion sweep in
// a head-sha concurrency lane while comment revocations run in the
// PR-number lane's '-comment' suffix family (#628), and the Actions API
// does not expose another run's
// targets, so two runs of the same PR can overlap. Each run registers its
// resolved targets as a status on the revocation anchor BEFORE reading the
// registry, defers to any newer live lane sharing a PR, and resolves its
// lane however it ends. Deferring loses nothing: the newer lane sweeps the
// shared PRs. The registry complements superseded(), which still drains
// stale runs behind a queued push sweep without touching the anchor.
const laneContext = 'panel/lane';
// A lane outlives its run only when the run died without resolving it; the
// workflow times out at 10 minutes, so double that retires orphans.
const LANE_TTL_MS = 20 * 60 * 1000;
const LANE = /^run-([1-9][0-9]*):pr-([0-9,]+|all)$/;
function laneDescription(numbers, name, runId) {
  return `run-${runId}:pr-${name === 'push' ? 'all' : numbers.join(',')}`;
}
// Best-effort writes: a lane that cannot persist only re-opens the small
// overlap window the registry closes, so quota errors propagate but an
// ordinary write failure is logged, not fatal. Returns the lane key.
async function postLane(api, numbers, name) {
  if (!numbers.length) return null;
  const runId = Number(process.env.GITHUB_RUN_ID);
  demand(Number.isSafeInteger(runId) && runId > 0, 'invalid run id for lane');
  const description = laneDescription(numbers, name, runId);
  try {
    await api.call(`statuses/${policy.revocationAnchor}`, 'POST', {state: 'pending', context: laneContext, description});
    return description;
  } catch (error) {
    if (error instanceof RateLimitError) throw error;
    console.error(`lane registration failed; continuing without it: ${error.message}`);
    return null;
  }
}
async function closeLane(api, description, ok) {
  if (!description) return;
  try {
    await api.call(`statuses/${policy.revocationAnchor}`, 'POST',
      {state: ok ? 'success' : 'error', context: laneContext, description});
  } catch (error) {
    if (error instanceof RateLimitError) throw error;
    console.error(`lane resolution failed; the TTL retires it: ${error.message}`);
  }
}
// The statuses API lists newest first, so the first record per lane key is
// the current one; malformed lane records fail closed like every other
// record read from the trusted anchor.
async function overlappingNewerLane(api, numbers) {
  const self = Number(process.env.GITHUB_RUN_ID);
  demand(Number.isSafeInteger(self) && self > 0, 'invalid run id for lane check');
  if (!numbers.length) return false;
  const mine = new Set(numbers);
  const latest = new Map();
  for (const record of await api.pages(`commits/${policy.revocationAnchor}/statuses`)) {
    if (record.context !== laneContext || latest.has(record.description)) continue;
    latest.set(record.description, record);
  }
  for (const [description, record] of latest) {
    if (record.state !== 'pending') continue;
    const match = LANE.exec(description || '');
    demand(match, `invalid lane record: ${description}`);
    const age = Date.now() - Date.parse(record.created_at);
    demand(Number.isFinite(age), 'invalid lane record epoch');
    if (age > LANE_TTL_MS) continue;
    if (Number(match[1]) <= self) continue;
    if (match[2] === 'all' || match[2].split(',').some(n => mine.has(Number(n)))) return true;
  }
  return false;
}

async function targets(api, name, event) {
  const eligible = p => p.base.ref === policy.baseBranch && !p.draft;
  if (name === 'issue_comment' || name === 'workflow_dispatch') {
    const number = name === 'issue_comment' ? event.issue.number : Number(event.inputs.pr_number);
    demand(Number.isSafeInteger(number) && number > 0, 'invalid PR number');
    const pr = await api.call(`pulls/${number}`);
    return pr.state === 'open' && eligible(pr) ? [number] : [];
  }
  const open = (await api.pages('pulls?state=open')).filter(eligible);
  if (name !== 'workflow_run') return open.map(p => p.number);
  // Main-push CI completions are covered by the gate's own push sweep; every other
  // run event (pull_request, or workflow_dispatch under manual PR CI) sweeps here.
  if (event.workflow_run.event === 'push') return [];
  // pull_requests can be empty for runs from forks and never exists on
  // workflow_dispatch runs, so the run's head SHA matches too.
  const run = event.workflow_run, named = new Set((run.pull_requests || []).map(p => p.number));
  return open.filter(p => named.has(p.number) || p.head.sha === run.head_sha).map(p => p.number);
}
async function main() {
  demand(process.env.GITHUB_REF === `refs/heads/${policy.baseBranch}`, 'run verifier only from trusted main');
  const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const api = new API(process.env.GITHUB_REPOSITORY, process.env.GITHUB_TOKEN);
  const name = process.env.GITHUB_EVENT_NAME;
  // Each wake verifies only the PRs its event can change (see targets); a push to main sweeps all.
  // queue:max reduces pending-event loss,
  // but overflow/lost delivery before ledger persistence cannot be recovered.
  const allowed = ['issue_comment', 'workflow_dispatch', 'workflow_run', 'push'];
  demand(allowed.includes(name), 'unsupported event');
  if (name === 'issue_comment' && !event.issue.pull_request) return;
  if (name === 'issue_comment') await revokeEvent(api, event);
  // Revocation latches above persist even on a stale run; the sweep below is
  // superseded work when a newer run waits in the serialized queue.
  if (await superseded(api)) {
    console.log('A newer queued run supersedes this one; skipping the sweep.');
    return;
  }
  const numbers = await targets(api, name, event);
  const lane = await postLane(api, numbers, name);
  let failed = false;
  try {
    if (await overlappingNewerLane(api, numbers)) {
      console.log('A newer run covering these PRs supersedes this one; skipping the sweep.');
      return;
    }
    const sweep = {};
    for (const number of numbers) {
      try { await verify(api, number, sweep); }
      catch (error) {
        failed = true; console.error(`PR #${number}: ${error.message}`);
        if (error instanceof RateLimitError) { console.error('Stopping the sweep: the token is out of quota.'); break; }
      }
    }
  } catch (error) {
    failed = true;
    throw error;
  } finally {
    await closeLane(api, lane, !failed);
  }
  if (failed) process.exitCode = 1;
}
module.exports = {parse, panel, jobsPass, dco, verify, revokeEvent, revocations, superseded, targets, postLane, closeLane, overlappingNewerLane, laneContext, API, RateLimitError};
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
