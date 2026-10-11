// SPDX-License-Identifier: MIT
'use strict';
const fs = require('node:fs');
const policy = require('./policy.json');
const SHA = /^[0-9a-f]{40}$/;
const keys = ['schema', 'lens', 'head', 'verdict', 'scope', 'independently_run',
  'author_reported', 'uncertainty', 'prior_findings', 'blockers'];
function demand(ok, message) { if (!ok) throw new Error(message); }
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
  demand(['APPROVE', 'CHANGES_REQUIRED'].includes(value.verdict), 'verdict');
  demand(typeof value.scope === 'string' && value.scope.trim().length > 0, 'scope required');
  for (const field of keys.slice(5)) {
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
  demand(jobs.length === names.length, 'unexpected job count');
  demand(new Set(jobs.map(j => j.name)).size === names.length, 'duplicate jobs');
  for (const name of names) {
    const job = jobs.find(j => j.name === name);
    demand(job && job.head_sha === head && job.status === 'completed' && job.conclusion === 'success', `job not green: ${name}`);
  }
}
function dco(commits) {
  demand(commits.length > 0, 'empty commit range');
  for (const commit of commits) {
    if (commit.parents.length > 1) continue; // Existing project policy exempts merge commits.
    const author = commit.commit.author;
    demand(author?.name && author?.email, 'missing commit author');
    const line = `Signed-off-by: ${author.name} <${author.email}>`;
    demand(commit.commit.message.split(/\r?\n/).includes(line), `missing author signoff: ${commit.sha}`);
  }
}
class API {
  constructor(repo, token) { this.repo = repo; this.token = token; }
  async call(path, method = 'GET', data) {
    const response = await fetch(`https://api.github.com/repos/${this.repo}/${path}`, {
      method, headers: {'Authorization': `Bearer ${this.token}`, 'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json'},
      ...(data ? {body: JSON.stringify(data)} : {})
    });
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
async function revocations(api, number, head) {
  const [ledger, legacy] = await Promise.all([
    api.pages(`commits/${policy.revocationAnchor}/statuses`), api.pages(`commits/${head}/statuses`)
  ]);
  const revoked = {};
  for (const record of [...ledger.filter(r => r.context === ledgerContext(number)),
    ...legacy.filter(r => r.context === 'panel/deleted-verdict')]) {
    const match = /^(principal|architect|qa):([1-9][0-9]*)$/.exec(record.description || '');
    const epoch = Date.parse(record.created_at);
    demand(match && Number.isSafeInteger(Number(match[2])) && Number.isFinite(epoch), 'invalid revocation record');
    const lens = match[1], previous = revoked[lens];
    revoked[lens] = {id: Math.max(previous?.id || 0, Number(match[2])), epoch: Math.max(previous?.epoch || 0, epoch)};
  }
  // Stable order, independent of API status pagination/order.
  return Object.fromEntries(Object.keys(policy.reviewers).filter(lens => revoked[lens]).map(lens => [lens, revoked[lens]]));
}
async function revokeEvent(api, event) {
  if (!['edited', 'deleted'].includes(event.action) || !event.issue?.pull_request) return;
  const id = event.comment?.user?.id;
  const oldBody = event.action === 'edited' ? event.changes?.body?.from : event.comment?.body;
  if (!Object.values(policy.reviewers).some(ids => ids.includes(id)) || !oldBody?.includes('```panel-verdict')) return;
  let lenses = Object.keys(policy.reviewers);
  try {
    const marker = parse(oldBody);
    demand(policy.reviewers[marker.lens].includes(id), 'revoked marker wrong publisher');
    lenses = [marker.lens];
  } catch { /* Malformed trusted marker revokes every lens, even on a stale head. */ }
  const pr = await api.call(`pulls/${event.issue.number}`);
  // Revoke the CURRENT head even when the removed marker names another SHA.
  await api.call(`statuses/${pr.head.sha}`, 'POST', {
    state: 'failure', context: policy.context, description: 'Verdict edited/deleted; require fresh panel attestations'
  });
  const comments = await api.pages(`issues/${event.issue.number}/comments`);
  const highWater = Math.max(event.comment.id, ...comments.map(c => c.id));
  demand(Number.isSafeInteger(highWater) && highWater > 0, 'invalid comment high-water ID');
  demand(SHA.test(policy.revocationAnchor), 'invalid revocation anchor');
  for (const lens of lenses) {
    // GitHub's server-generated created_at supplies the revocation epoch.
    await api.call(`statuses/${policy.revocationAnchor}`, 'POST', {
      state: 'error', context: ledgerContext(event.issue.number), description: `${lens}:${highWater}`
    });
  }

}
async function workflows(api, number, head) {
  const runs = await api.pages(`actions/runs?event=pull_request&head_sha=${head}`, 'workflow_runs');
  const checked = [];
  for (const [path, names] of Object.entries(policy.workflows)) {
    const matches = r => r.path === path && r.head_sha === head && r.event === 'pull_request' &&
      r.repository?.full_name === api.repo && r.pull_requests?.some(p => p.number === number);
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
async function verify(api, number) {
  const pr = await api.call(`pulls/${number}`);
  demand(pr.state === 'open' && !pr.draft && pr.base.ref === policy.baseBranch, 'not an open ready main PR');
  const head = pr.head.sha, base = pr.base.sha;
  demand(SHA.test(head) && SHA.test(base), 'bad PR SHA');
  const status = (state, description) => api.call(`statuses/${head}`, 'POST', {
    state, context: policy.context, description: description.slice(0, 140),
    target_url: `https://github.com/${api.repo}/actions/runs/${process.env.GITHUB_RUN_ID}`
  });
  await status('pending', 'Checking current head panel, CI, DCO and policy');
  try {
    const currentBase = await api.call(`git/ref/heads/${policy.baseBranch}`);
    demand(currentBase.object.sha === base, 'main moved during validation');
    const compare = await api.call(`compare/${base}...${head}`);
    demand(compare.status === 'ahead' && compare.merge_base_commit.sha === base, 'update branch against current main and retest');
    // Compare exact bytes via Git objects. Missing files on both sides are OK at bootstrap.
    for (const path of policy.protectedFiles) {
      async function blob(ref) {
        try { return await api.call(`contents/${path}?ref=${ref}`); }
        catch (error) { if (error.message.startsWith('GitHub API 404:')) return null; throw error; }
      }
      const [before, after] = await Promise.all([blob(base), blob(head)]);
      function identity(item) {
        if (Array.isArray(item)) return JSON.stringify(item.map(x => [x.name, x.sha, x.type]).sort());
        return item?.sha ?? null;
      }
      demand(identity(before) === identity(after), `protected policy changed: ${path}`);
    }
    const comments = await api.pages(`issues/${number}/comments`);
    const revoked = await revocations(api, number, head);
    panel(comments, head, revoked);
    dco(await api.pages(`pulls/${number}/commits`));
    const checkedRuns = await workflows(api, number, head);
    // Repeat the whole selection, latest attempt and job inspection, not just PR facts.
    // Recheck live facts immediately before publishing. New head never inherits success.
    const [lastPR, lastBase, lastComments, lastRevoked, lastRuns] = await Promise.all([
      api.call(`pulls/${number}`), api.call(`git/ref/heads/${policy.baseBranch}`), api.pages(`issues/${number}/comments`),
      revocations(api, number, head), workflows(api, number, head)
    ]);
    demand(JSON.stringify(lastRuns) === JSON.stringify(checkedRuns), 'CI runs/attempts/jobs changed during verification');
    demand(lastPR.state === 'open' && !lastPR.draft && lastPR.head.sha === head &&
      lastPR.base.sha === base && lastPR.base.ref === policy.baseBranch && lastBase.object.sha === base, 'PR/main changed during verification');
    demand(JSON.stringify(lastRevoked) === JSON.stringify(revoked), 'revocations changed during verification');
    panel(lastComments, head, lastRevoked);
    await status('success', '3 exact-head lens approvals; 13 green jobs; DCO; unchanged gate policy');
  } catch (error) {
    await status('failure', error.message);
    throw error;
  }
}
async function main() {
  demand(process.env.GITHUB_REF === `refs/heads/${policy.baseBranch}`, 'run verifier only from trusted main');
  const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const api = new API(process.env.GITHUB_REPOSITORY, process.env.GITHUB_TOKEN);
  const name = process.env.GITHUB_EVENT_NAME;
  // Every wake sweeps all open main PRs. queue:max reduces pending-event loss,
  // but overflow/lost delivery before ledger persistence cannot be recovered.
  const allowed = ['issue_comment', 'workflow_dispatch', 'workflow_run', 'push'];
  demand(allowed.includes(name), 'unsupported event');
  if (name === 'workflow_run' && event.workflow_run.event !== 'pull_request') return;
  if (name === 'issue_comment' && !event.issue.pull_request) return;
  if (name === 'workflow_dispatch') {
    const number = Number(event.inputs.pr_number);
    demand(Number.isSafeInteger(number) && number > 0, 'invalid PR number');
  }
  if (name === 'issue_comment') await revokeEvent(api, event);
  const numbers = (await api.pages('pulls?state=open')).filter(p =>
    p.base.ref === policy.baseBranch && !p.draft).map(p => p.number);
  let failed = false;
  for (const number of numbers) {
    try { await verify(api, number); }
    catch (error) { failed = true; console.error(`PR #${number}: ${error.message}`); }
  }
  if (failed) process.exitCode = 1;
}
module.exports = {parse, panel, jobsPass, dco, verify, revokeEvent, revocations, API};
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
