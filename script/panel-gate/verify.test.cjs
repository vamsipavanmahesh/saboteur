// SPDX-License-Identifier: MIT
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {parse, panel, jobsPass, dco, verify} = require('./verify.cjs');
const policy = require('./policy.json');
const HEAD = 'a'.repeat(40), BASE = 'b'.repeat(40);
const marker = (changes = {}) => ({schema: 1, lens: 'principal', head: HEAD,
  verdict: 'APPROVE', scope: 'Full PR diff', independently_run: [], author_reported: ['CI'],
  uncertainty: ['Static review only'], prior_findings: [], blockers: [], ...changes});
const body = value => '```panel-verdict\n' + JSON.stringify(value, null, 2) + '\n```\nOptional human-readable discussion.';
const comments = () => ['principal', 'architect', 'qa'].map((lens, i) => ({
  id: i + 1, user: {id: 1875074}, body: body(marker({lens}))}));
test('canonical exact-head distinct lenses pass under one explicitly trusted publisher', () => {
  assert.equal(parse(body(marker())).head, HEAD);
  assert.deepEqual(Object.keys(panel(comments(), HEAD)), ['principal', 'architect', 'qa']);
});
for (const [label, change] of Object.entries({shortSHA: {head: 'aaaaaaa'}, upperSHA: {head: 'A'.repeat(40)},
  wrongSchema: {schema: '1'}, unknownLens: {lens: 'security'}, coercion: {scope: 1},
  scalarEvidence: {independently_run: 'npm test'}, missingEvidence: {author_reported: undefined},
  approvalWithBlocker: {blockers: ['bug']}, noChangesBlocker: {verdict: 'CHANGES_REQUIRED'},
  unknownKey: {admin_approved: true}, badVerdict: {verdict: 'approve'}})) {
  test(`reject ${label}`, () => assert.throws(() => parse(body(marker(change)))));
}
test('reject prose, quotes, duplicate blocks and duplicate JSON keys', () => {
  for (const text of ['APPROVE at ' + HEAD, '> ' + body(marker()), 'prefix\n' + body(marker()),
    body(marker()) + body(marker()), body(marker()).replace('"schema": 1,', '"schema": 1,\n  "schema": 1,')]) {
    assert.throws(() => parse(text));
  }
});
test('untrusted comment cannot fill missing lens or revoke a trusted approval', () => {
  const c = comments(); c[2].user.id = 666;
  assert.throws(() => panel(c, HEAD));
  assert.doesNotThrow(() => panel([...comments(), {id: 9, user: {id: 666}, body: '```panel-verdict BAD'}], HEAD));
});
test('latest ID wins even with old SHA; blocker, malformed edit, deletion invalidate', () => {
  for (const value of [marker({lens: 'qa', head: BASE}), marker({lens: 'qa', verdict: 'CHANGES_REQUIRED', blockers: ['bug']})]) {
    assert.throws(() => panel([...comments(), {id: 10, user: {id: 1875074}, body: body(value)}], HEAD));
  }
  const edited = comments(); edited[1].body = '```panel-verdict malformed';
  assert.throws(() => panel(edited, HEAD));
  assert.throws(() => panel(comments().slice(0, 2), HEAD));
  assert.throws(() => panel(comments(), BASE));
});
test('same lens three times cannot substitute for three lenses', () => {
  assert.throws(() => panel(comments().map(c => ({...c, body: body(marker())})), HEAD));
});
test('exact successful jobs only, no skip/neutral/duplicate/old-head/missing', () => {
  const jobs = [{name: 'test', head_sha: HEAD, status: 'completed', conclusion: 'success'}];
  jobsPass(jobs, ['test'], HEAD);
  for (const change of [{conclusion: 'skipped'}, {conclusion: 'neutral'}, {status: 'in_progress'}, {head_sha: BASE}, {name: 'other'}]) {
    assert.throws(() => jobsPass([{...jobs[0], ...change}], ['test'], HEAD));
  }
  assert.throws(() => jobsPass([...jobs, ...jobs], ['test', 'lint'], HEAD));
  assert.throws(() => jobsPass([], ['test'], HEAD));
});
test('author-matching whole-line DCO, no substring/coercion', () => {
  const commit = {sha: HEAD, parents: [{}], commit: {author: {name: 'Name', email: 'name@example.org'},
    message: 'subject\n\nSigned-off-by: Name <name@example.org>'}};
  dco([commit]);
  for (const message of ['prefix Signed-off-by: Name <name@example.org>', 'Signed-off-by: Other <name@example.org>', 'Signed-off-by: Name <name@example.org> suffix']) {
    assert.throws(() => dco([{...commit, commit: {...commit.commit, message}}]));
  }
  assert.throws(() => dco([]));
});
function fakeAPI(change = {}) {
  const statuses = [];
  const pr = {number: 1, state: 'open', draft: false, base: {ref: 'main', sha: BASE}, head: {sha: HEAD}};
  let reads = 0;
  const runs = Object.keys(policy.workflows).map((path, i) => ({id: i + 1, path, head_sha: HEAD,
    event: 'pull_request', repository: {full_name: 'owner/repo'}, pull_requests: [{number: 1}]}));
  return {repo: 'owner/repo', statuses,
    async call(path, method, data) {
      if (method === 'POST') { statuses.push(data); return data; }
      if (path === 'pulls/1') { reads++; return reads > 1 && change.newHead ? {...pr, head: {sha: BASE}} : pr; }
      if (path === 'git/ref/heads/main') return {object: {sha: change.movedBase ? HEAD : BASE}};
      if (path.startsWith('compare/')) return {status: 'ahead', merge_base_commit: {sha: change.behind ? HEAD : BASE}};
      if (path.startsWith('contents/')) return {sha: change.policyEdit && path.endsWith(HEAD) ? HEAD : BASE};
      if (path.startsWith('actions/runs/')) return {head_sha: HEAD, status: 'completed', conclusion: 'success', run_attempt: 2};
      throw new Error('unexpected call ' + path);
    },
    async pages(path) {
      if (path.startsWith('commits/')) return [];
      if (path === 'issues/1/comments') return change.noQA ? comments().slice(0, 2) : comments();
      if (path === 'pulls/1/commits') return [{sha: HEAD, parents: [{}], commit: {
        author: {name: 'Name', email: 'name@example.org'}, message: 'Signed-off-by: Name <name@example.org>'}}];
      if (path.startsWith('actions/runs?')) return change.wrongRun ? runs.map(r => ({...r, head_sha: BASE})) : runs;
      const id = Number(path.split('/')[2]);
      return policy.workflows[runs[id - 1].path].map(name => ({name, head_sha: HEAD, status: 'completed', conclusion: change.skipped ? 'skipped' : 'success'}));
    }
  };
}
test('end-to-end API decision posts pending then success for current facts', async () => {
  const api = fakeAPI(); await verify(api, 1);
  assert.deepEqual(api.statuses.map(s => s.state), ['pending', 'success']);
});
for (const fault of ['newHead', 'movedBase', 'behind', 'policyEdit', 'noQA', 'wrongRun', 'skipped']) {
  test(`API decision fails closed: ${fault}`, async () => {
    const api = fakeAPI({[fault]: true}); await assert.rejects(() => verify(api, 1));
    assert.deepEqual(api.statuses.map(s => s.state), ['pending', 'failure']);
  });
}

test('deleted newer verdict cannot uncover an older approval', () => {
  assert.throws(() => panel(comments(), HEAD, {qa: 8}));
  assert.doesNotThrow(() => panel([...comments(), {id: 9, user: {id: 1875074}, body: body(marker({lens: 'qa'}))}], HEAD, {qa: 8}));
});
test('editing an older comment to a blocking verdict wins by update time', () => {
  const c = comments().map(x => ({...x, updated_at: '2026-10-10T00:00:00Z'}));
  c.push({id: 9, user: {id: 1875074}, updated_at: '2026-10-11T00:00:00Z', body: body(marker())});
  c[0].updated_at = '2026-10-12T00:00:00Z';
  c[0].body = body(marker({verdict: 'CHANGES_REQUIRED', blockers: ['new bug']}));
  assert.throws(() => panel(c, HEAD));
});
