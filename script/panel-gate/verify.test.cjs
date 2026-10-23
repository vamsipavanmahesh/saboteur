// SPDX-License-Identifier: MIT
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {parse, panel, jobsPass, dco, verify, revokeEvent, revocations, superseded, postLane, closeLane, overlappingNewerLane} = require('./verify.cjs');
const policy = require('./policy.json');
const HEAD = 'a'.repeat(40), BASE = 'b'.repeat(40);
const marker = (changes = {}) => {
  const value = {schema: 1, lens: 'owner', head: HEAD,
    verdict: 'APPROVE', scope: 'Full PR diff', independently_run: [], author_reported: ['CI'],
    uncertainty: ['Static review only'], prior_findings: [], blockers: [], ...changes};
  if (!Object.hasOwn(value, 'human_approval')) {
    value.human_approval = value.verdict === 'APPROVE' ? {head: value.head, note: 'user approved this exact head'} : null;
  }
  return value;
};
const body = value => '```panel-verdict\n' + JSON.stringify(value, null, 2) + '\n```\nOptional human-readable discussion.';
const comments = () => [{id: 1, created_at: '2026-10-10T00:00:00Z', user: {id: 1875074}, body: body(marker())}];
test('a canonical exact-head owner approval passes', () => {
  assert.equal(parse(body(marker())).head, HEAD);
  assert.deepEqual(Object.keys(panel(comments(), HEAD)), ['owner']);
});
test('approval markers bind the human decision to the exact head', () => {
  assert.throws(() => parse(body(marker({human_approval: null}))), /human decision/);
  assert.throws(() => parse(body(marker({human_approval: {head: BASE, note: 'other head'}}))), /human decision/);
  assert.throws(() => parse(body(marker({human_approval: {head: HEAD, note: ' '}}))), /human decision/);
  assert.throws(() => parse(body(marker({verdict: 'CHANGES_REQUIRED', blockers: ['b'], human_approval: {head: HEAD, note: 'x'}}))), /no human approval/);
  assert.doesNotThrow(() => parse(body(marker({verdict: 'CHANGES_REQUIRED', blockers: ['b']}))));
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
  const c = comments(); c[0].user.id = 666;
  assert.throws(() => panel(c, HEAD));
  assert.doesNotThrow(() => panel([...comments(), {id: 9, user: {id: 666}, body: '```panel-verdict BAD'}], HEAD));
});
test('CHANGES_REQUESTED spelling parses as CHANGES_REQUIRED, blockers still required (#278)', () => {
  const requested = parse(body(marker({verdict: 'CHANGES_REQUESTED', blockers: ['bug']})));
  assert.equal(requested.verdict, 'CHANGES_REQUIRED');
  assert.throws(() => parse(body(marker({verdict: 'CHANGES_REQUESTED'}))));
});
test('a superseded CHANGES_REQUESTED marker does not poison newer approvals (#278)', () => {
  const stale = {id: 0, created_at: '2026-10-09T00:00:00Z', user: {id: 1875074},
    body: body(marker({lens: 'owner', verdict: 'CHANGES_REQUESTED', blockers: ['old bug']}))};
  assert.deepEqual(Object.keys(panel([stale, ...comments()], HEAD)), ['owner']);
});
test('a latest CHANGES_REQUESTED marker still blocks (#278)', () => {
  const c = [...comments(), {id: 10, user: {id: 1875074},
    body: body(marker({lens: 'owner', verdict: 'CHANGES_REQUESTED', blockers: ['bug']}))}];
  assert.throws(() => panel(c, HEAD));
});
test('latest ID wins even with old SHA; blocker, malformed edit, deletion invalidate', () => {
  for (const value of [marker({lens: 'owner', head: BASE}), marker({lens: 'owner', verdict: 'CHANGES_REQUIRED', blockers: ['bug']})]) {
    assert.throws(() => panel([...comments(), {id: 10, user: {id: 1875074}, body: body(value)}], HEAD));
  }
  const edited = comments(); edited[0].body = '```panel-verdict malformed';
  assert.throws(() => panel(edited, HEAD));
  assert.throws(() => panel([], HEAD));
  assert.throws(() => panel(comments(), BASE));
});
test('aggregate checks: named jobs green on the exact head; other records are inputs', () => {
  const ci = {name: 'ci-passed', head_sha: HEAD, status: 'completed', conclusion: 'success'};
  const input = {name: 'Ruby 4.0 / linux / shard 1', head_sha: HEAD, status: 'completed', conclusion: 'failure'};
  // The aggregator's own inputs never change the gate's verdict, red ones included.
  jobsPass([ci, input], ['ci-passed'], HEAD);
  jobsPass([ci], ['ci-passed'], HEAD);
  for (const change of [{conclusion: 'failure'}, {conclusion: 'skipped'}, {conclusion: 'neutral'},
      {status: 'in_progress'}, {head_sha: BASE}]) {
    assert.throws(() => jobsPass([{...ci, ...change}, input], ['ci-passed'], HEAD));
  }
  assert.throws(() => jobsPass([input], ['ci-passed'], HEAD), /exactly one/);
  assert.throws(() => jobsPass([ci, ci], ['ci-passed'], HEAD), /exactly one/);
});
test('author-matching whole-line DCO, no substring/coercion', () => {
  const commit = {sha: HEAD, parents: [{}], commit: {author: {name: 'Name', email: 'name@example.org'},
    message: 'subject\n\nSigned-off-by: Name <name@example.org>'}};
  dco([commit]);
  for (const message of ['prefix Signed-off-by: Name <name@example.org>', 'Signed-off-by: Other <name@example.org>', 'Signed-off-by: Name <name@example.org> suffix',
      'subject  Signed-off-by: Name <name@example.org>',
      'subject\n\nbody mentions Signed-off-by: Name <name@example.org> mid-sentence\n\nReviewed-by: R <r@example.org>',
      'subject\n\nSigned-off-by: Name <name@example.org>\n\ntrailing paragraph']) {
    assert.throws(() => dco([{...commit, commit: {...commit.commit, message}}]), message);
  }
  dco([{...commit, commit: {...commit.commit,
    message: 'subject\n\nSigned-off-by: Name <name@example.org>\nReviewed-by: R <r@example.org>'}}]);
  for (const message of ['Signed-off-by: Name <name@example.org>',
      'subject\nSigned-off-by: Name <name@example.org>']) {
    assert.throws(() => dco([{...commit, commit: {...commit.commit, message}}]), message);
  }
  assert.throws(() => dco([]));
});
function fakeAPI(change = {}) {
  const statuses = [];
  const pr = {number: 1, state: 'open', draft: false, base: {ref: 'main', sha: BASE}, head: {sha: HEAD}};
  let reads = 0;
  const runs = Object.keys(policy.workflows).map((path, i) => ({id: i + 1, path, head_sha: HEAD,
    event: change.dispatchRun && path.endsWith('ci.yml') ? 'workflow_dispatch' : 'pull_request',
    repository: {full_name: 'owner/repo'}, pull_requests: change.dispatchRun && path.endsWith('ci.yml') ? [] : [{number: 1}]}));
  return {repo: 'owner/repo', statuses,
    async call(path, method, data) {
      if (method === 'POST') { statuses.push(data); return data; }
      if (path === 'pulls/1') { reads++; return reads > 1 && change.newHead ? {...pr, head: {sha: BASE}} : pr; }
      if (path.startsWith('compare/')) return {status: change.behind ? 'behind' : change.movedBase ? 'diverged' : 'ahead', merge_base_commit: {sha: BASE}};
      if (path.startsWith('contents/')) return {sha: change.policyEdit && path.endsWith(HEAD) ? HEAD : BASE};
      if (path.startsWith('actions/runs/')) return {...runs[Number(path.split('/')[2]) - 1], status: 'completed', conclusion: 'success', run_attempt: 2};
      throw new Error('unexpected call ' + path);
    },
    async pages(path) {
      if (path.startsWith('commits/') || path === 'issues/1/events' || path === 'issues/2/events') return [];
      if (path === 'issues/1/comments') return change.noComments ? [] : comments();
      if (path === 'pulls/1/commits' || path === 'pulls/2/commits') return [{sha: HEAD, parents: [{}], commit: {
        author: {name: 'Name', email: 'name@example.org'}, message: 'subject\n\nSigned-off-by: Name <name@example.org>'}}];
      if (path.startsWith('actions/runs?')) return change.wrongRun ? runs.map(r => ({...r, head_sha: BASE})) : runs;
      const id = Number(path.split('/')[2]);
      const list = policy.workflows[runs[id - 1].path].map(name => ({name, head_sha: HEAD, status: 'completed', conclusion: change.skipped ? 'skipped' : 'success'}));
      return list;
    }
  };
}

test('superseded: only a strictly newer pending run of the same workflow skips the sweep', async () => {
  const seen = [];
  const pushes = {pages: async (path, field) => { seen.push([path, field]); return [{id: 40, event: 'push'}, {id: 42, event: 'push'}]; }};
  process.env.GITHUB_RUN_ID = '41';
  process.env.GITHUB_WORKFLOW_REF = 'owner/repo/.github/workflows/panel-gate.yml@refs/heads/main';
  assert.equal(await superseded(pushes), true);
  assert.deepEqual(seen[0], ['actions/workflows/panel-gate.yml/runs?status=pending', 'workflow_runs']);
  process.env.GITHUB_RUN_ID = '42';
  assert.equal(await superseded(pushes), false);
  process.env.GITHUB_RUN_ID = '99';
  assert.equal(await superseded(pushes), false);
});

test('superseded: a newer run scoped to another PR never skips this run', async () => {
  // QA blocker on #404: comment, dispatch and CI-completion runs verify only
  // their own PRs, so in a mixed-PR backlog they cannot supersede anything.
  process.env.GITHUB_RUN_ID = '41';
  process.env.GITHUB_WORKFLOW_REF = 'owner/repo/.github/workflows/panel-gate.yml@refs/heads/main';
  const comments = {pages: async () => [{id: 42, event: 'issue_comment'}, {id: 43, event: 'workflow_run'}, {id: 44, event: 'workflow_dispatch'}]};
  assert.equal(await superseded(comments), false);
  const mixed = {pages: async () => [{id: 42, event: 'issue_comment'}, {id: 43, event: 'push'}]};
  assert.equal(await superseded(mixed), true);
});
test('superseded demands a valid run identity before spending API calls', async () => {
  process.env.GITHUB_RUN_ID = 'not-a-number';
  process.env.GITHUB_WORKFLOW_REF = 'owner/repo/.github/workflows/panel-gate.yml@refs/heads/main';
  let called = false;
  await assert.rejects(() => superseded({pages: async () => { called = true; return []; }}));
  assert.equal(called, false);
});
test('end-to-end API decision posts pending then success for current facts', async () => {
  const api = fakeAPI(); await verify(api, 1);
  assert.deepEqual(api.statuses.map(s => s.state), ['pending', 'success']);
});
test('a protected change needs the owner approval marker on the exact head', async () => {
  const api = fakeAPI({policyEdit: true});
  await verify(api, 1);
  assert.deepEqual(api.statuses.map(s => s.state), ['pending', 'success']);
  assert.match(api.statuses.at(-1).description, /user-approved protected change/);
  const bare = fakeAPI({policyEdit: true, noComments: true});
  await assert.rejects(() => verify(bare, 1));
  assert.deepEqual(bare.statuses.map(s => s.state), ['pending', 'failure']);
});
test('no approval marker is required when protected paths are untouched', async () => {
  const api = fakeAPI({noComments: true});
  await verify(api, 1);
  assert.deepEqual(api.statuses.map(s => s.state), ['pending', 'success']);
  assert.match(api.statuses.at(-1).description, /no protected paths changed/);
});
// Manual PR CI: a workflow_dispatch run of ci.yml on the exact head is as good a
// current-head workflow as a pull_request run.
test('end-to-end decision accepts a manually dispatched CI run on the head', async () => {
  const api = fakeAPI({dispatchRun: true}); await verify(api, 1);
  assert.deepEqual(api.statuses.map(s => s.state), ['pending', 'success']);
});
test('a head that trails a moved main still passes when its checks are green', async () => {
  const api = fakeAPI({movedBase: true}); await verify(api, 1);
  assert.deepEqual(api.statuses.map(s => s.state), ['pending', 'success']);
});
for (const fault of ['newHead', 'behind', 'wrongRun', 'skipped']) {
  test(`API decision fails closed: ${fault}`, async () => {
    const api = fakeAPI({[fault]: true}); await assert.rejects(() => verify(api, 1));
    assert.deepEqual(api.statuses.map(s => s.state), ['pending', 'failure']);
  });
}

test('deleted newer verdict cannot uncover an older approval', () => {
  assert.throws(() => panel(comments(), HEAD, {owner: {id: 8, epoch: Date.parse('2026-10-11T00:00:00Z')}}));
  assert.doesNotThrow(() => panel([...comments(), {id: 9, created_at: '2026-10-12T00:00:00Z', user: {id: 1875074}, body: body(marker({lens: 'owner'}))}], HEAD, {owner: {id: 8, epoch: Date.parse('2026-10-11T00:00:00Z')}}));
});
test('editing an older comment to a blocking verdict wins by update time', () => {
  const c = comments().map(x => ({...x, updated_at: '2026-10-10T00:00:00Z'}));
  c.push({id: 9, user: {id: 1875074}, updated_at: '2026-10-11T00:00:00Z', body: body(marker())});
  c[0].updated_at = '2026-10-12T00:00:00Z';
  c[0].body = body(marker({verdict: 'CHANGES_REQUIRED', blockers: ['new bug']}));
  assert.throws(() => panel(c, HEAD));
});


// These regressions failed against PR #28's original verifier.
test('edited low-ID blocker deletion cannot resurrect a higher-ID old approval', () => {
  const c = comments();
  c.push({...c[0], id: 10, created_at: '2026-10-11T00:00:00Z'});
  assert.throws(() => panel(c, HEAD, {owner: {id: 10, epoch: Date.parse('2026-10-12T00:00:00Z')}}));
});
test('rerun starts after initial green CI read: never publish success', async () => {
  const api = fakeAPI(), call = api.call.bind(api), seen = new Set();
  api.call = async (path, method, data) => {
    const result = await call(path, method, data);
    if (path.startsWith('actions/runs/') && method !== 'POST') {
      if (seen.has(path)) return {...result, status: 'in_progress', conclusion: null, run_attempt: 3};
      seen.add(path);
    }
    return result;
  };
  await assert.rejects(() => verify(api, 1));
  assert.equal(api.statuses.at(-1).state, 'failure');
});

function eventAPI() {
  // A protected change keeps the owner approval (and its revocation) on the
  // gate's decision path: without one no marker is demanded and a revoked
  // approval blocks nothing.
  const api = fakeAPI({policyEdit: true}), call = api.call.bind(api), pages = api.pages.bind(api);
  const records = [], current = comments();
  let epoch = '2026-10-12T00:00:00Z';
  api.comments = current;
  api.records = records;
  api.call = async (path, method, data) => {
    if (method === 'POST' && (data.context.startsWith('panel/revoked/') || data.context.startsWith('panel/revocation-intent/'))) {
      const record = {...data, created_at: epoch}; records.push(record); api.statuses.push(data); return record;
    }
    return call(path, method, data);
  };
  api.pages = async path => {
    if (path === `commits/${policy.revocationAnchor}/statuses`) return records;
    if (path === 'issues/1/comments') return current;
    return pages(path);
  };
  return api;
}
const deletion = (value, action = 'deleted') => ({action, issue: {number: 1, pull_request: {}},
  comment: {id: 1, user: {id: 1875074}, body: body(value)},
  ...(action === 'edited' ? {changes: {body: {from: body(value)}}} : {})});
for (const action of ['deleted', 'edited']) {
  for (const stale of [false, true]) {
    test(`${action} old-ID blocker ${stale ? 'on stale SHA' : 'on current SHA'} persists across heads`, async () => {
      const api = eventAPI();
      api.comments.push({...comments()[0], id: 10});
      await revokeEvent(api, deletion(marker({head: stale ? BASE : HEAD, verdict: 'CHANGES_REQUIRED', blockers: ['bug']}), action));
      assert.equal(api.records.length, 2);
      assert.equal(api.records[1].context, 'panel/revoked/pr-1');
      assert.equal(api.records[1].description, 'owner:10');
      const cutoff = await revocations(api, 1, HEAD);
      assert.throws(() => panel(api.comments, HEAD, cutoff));
      assert.deepEqual(await revocations(api, 1, BASE), cutoff);
      // An edit of an old approval is not a new attestation.
      api.comments.at(-1).updated_at = '2026-10-13T00:00:00Z';
      assert.throws(() => panel(api.comments, HEAD, cutoff));
      // ID alone is insufficient: comment existed before server revocation epoch.
      api.comments.push({...comments()[0], id: 11, created_at: '2026-10-12T00:00:00Z'});
      assert.throws(() => panel(api.comments, HEAD, cutoff));
      api.comments.push({...comments()[0], id: 12, created_at: '2026-10-13T00:00:01Z', updated_at: '2026-10-13T00:00:01Z'});
      assert.doesNotThrow(() => panel(api.comments, HEAD, cutoff));
      assert.deepEqual(await revocations(api, 2, HEAD), {});
    });
  }
}
test('malformed marker edit revokes all lenses; untrusted event cannot revoke', async () => {
  const api = eventAPI(), event = deletion(marker());
  event.comment.body = '```panel-verdict malformed';
  await revokeEvent(api, event);
  assert.deepEqual(Object.keys(await revocations(api, 1, HEAD)), ['owner']);
  event.comment.user.id = 666;
  await revokeEvent(api, event);
  assert.equal(api.records.length, 2);
});
test('revocation ledger failure cannot publish success', async () => {
  const api = fakeAPI(), pages = api.pages.bind(api);
  api.pages = async path => {
    if (path === `commits/${policy.revocationAnchor}/statuses`) throw new Error('ledger unavailable');
    return pages(path);
  };
  await assert.rejects(() => verify(api, 1), /ledger unavailable/);
  assert.equal(api.statuses.at(-1).state, 'failure');
});
for (const fault of ['newRun', 'newAttemptGreen', 'jobFailed', 'jobReplaced', 'newRevocation', 'ledgerError']) {
  test(`mid-verification ${fault} never publishes success`, async () => {
    const api = fakeAPI(), pages = api.pages.bind(api), call = api.call.bind(api);
    let runLists = 0, ledgerReads = 0;
    api.pages = async path => {
      if (path === `commits/${policy.revocationAnchor}/statuses` && ++ledgerReads > 1) {  // read 1 is the shared sweep read; read 2 is the live final re-check
        if (fault === 'ledgerError') throw new Error('ledger unavailable');
        if (fault === 'newRevocation') return [{context: 'panel/revoked/pr-1', description: 'owner:10', created_at: '2026-10-12T00:00:00Z'}];
      }
      const result = await pages(path);
      if (path.startsWith('actions/runs?')) {
        runLists++;
        if (runLists > 1 && fault === 'newRun') return [...result, {...result[0], id: 99}];
      }
      if (path.includes('/jobs') && runLists > 1) {
        if (fault === 'jobFailed') return result.map((j, i) => i ? j : {...j, conclusion: 'failure'});
        if (fault === 'jobReplaced') return result.map((j, i) => ({...j, id: i + 100}));
      }
      return result;
    };
    api.call = async (path, method, data) => {
      if (path === 'actions/runs/99') return {id: 99, status: 'in_progress', conclusion: null};
      const result = await call(path, method, data);
      return path.startsWith('actions/runs/') && runLists > 1 && fault === 'newAttemptGreen' ? {...result, run_attempt: 3} : result;
    };
    await assert.rejects(() => verify(api, 1));
    assert.equal(api.statuses.at(-1).state, 'failure');
  });
}
for (const path of policy.protectedFiles) {
  test(`protected path owner-approved change passes; unapproved fails: ${path}`, async () => {
    const api = fakeAPI(), call = api.call.bind(api);
    api.call = async (p, method, data) => p === `contents/${path}?ref=${HEAD}` ? {sha: HEAD} : call(p, method, data);
    await verify(api, 1);
    assert.deepEqual(api.statuses.map(s => s.state), ['pending', 'success']);
    const bare = fakeAPI({noComments: true}), bareCall = bare.call.bind(bare);
    bare.call = async (p, method, data) => p === `contents/${path}?ref=${HEAD}` ? {sha: HEAD} : bareCall(p, method, data);
    await assert.rejects(() => verify(bare, 1));
    assert.deepEqual(bare.statuses.map(s => s.state), ['pending', 'failure']);
  });
}

test('revocation write/read errors revoke current head before stopping event handler', async () => {
  for (const fault of ['comments', 'write']) {
    const api = eventAPI(), call = api.call.bind(api), pages = api.pages.bind(api);
    api.call = async (path, method, data) => {
      if (fault === 'write' && method === 'POST' && (data.context.startsWith('panel/revoked/') || data.context.startsWith('panel/revocation-intent/'))) throw new Error('ledger write error');
      return call(path, method, data);
    };
    api.pages = async path => {
      if (fault === 'comments' && path === 'issues/1/comments') throw new Error('comments unavailable');
      return pages(path);
    };
    await assert.rejects(() => revokeEvent(api, deletion(marker({head: BASE}))));
    assert(api.statuses.some(s => s.context === policy.context && s.state === 'failure'));
  }
});
test('multiple revocations retain highest ID and epoch regardless of API order', async () => {
  const api = eventAPI();
  api.records.push({context: 'panel/revoked/pr-1', description: 'owner:20', created_at: '2026-10-12T00:00:00Z'},
    {context: 'panel/revoked/pr-1', description: 'owner:10', created_at: '2026-10-13T00:00:00Z'});
  assert.deepEqual(await revocations(api, 1, HEAD), {owner: {id: 20, epoch: Date.parse('2026-10-13T00:00:00Z')}});
});
test('invalid ledger record fails closed, never silently drops revocation', async () => {
  const api = eventAPI(); api.records.push({context: 'panel/revoked/pr-1', description: 'owner:10'});
  await assert.rejects(() => verify(api, 1), /invalid revocation record/);
  assert.equal(api.statuses.at(-1).state, 'failure');
});

test('failed revocation ledger write remains blocking after API recovery and subsequent sweeps', async () => {
  const api = eventAPI(), call = api.call.bind(api), pages = api.pages.bind(api);
  const headRecords = [];
  let fail = true;
  api.call = async (path, method, data) => {
    if (method === 'POST' && (data.context.startsWith('panel/revoked/') || data.context.startsWith('panel/revocation-intent/')) && fail) throw new Error('ledger transient failure');
    if (method === 'POST' && path === `statuses/${HEAD}`) headRecords.push({...data, created_at: '2026-10-12T00:00:00Z'});
    return call(path, method, data);
  };
  api.pages = async path => path === `commits/${HEAD}/statuses` ? headRecords : pages(path);
  await assert.rejects(() => revokeEvent(api, deletion(marker({head: BASE, verdict: 'CHANGES_REQUIRED', blockers: ['bug']}))));
  fail = false;
  await assert.rejects(() => verify(api, 1));
  await assert.rejects(() => verify(api, 1));
  assert(!api.statuses.some(s => s.state === 'success'));
});

for (const fault of ['comments', 'refinement', 'headLatch']) {
  for (const malformed of [false, true]) {
    test(`durable intent survives ${fault} failure (${malformed ? 'all lenses' : 'one lens'}) across subsequent sweeps`, async () => {
      const api = eventAPI(), call = api.call.bind(api), pages = api.pages.bind(api);
      let failing = true;
      api.call = async (path, method, data) => {
        if (failing && method === 'POST' && ((fault === 'refinement' && data.context.startsWith('panel/revoked/')) ||
          (fault === 'headLatch' && data.context === policy.context))) throw new Error('transient write failure');
        return call(path, method, data);
      };
      api.pages = async path => {
        if (failing && fault === 'comments' && path === 'issues/1/comments') throw new Error('transient comments failure');
        return pages(path);
      };
      const event = deletion(marker({head: BASE}));
      if (malformed) event.comment.body = '```panel-verdict malformed';
      await assert.rejects(() => revokeEvent(api, event));
      failing = false;
      await assert.rejects(() => verify(api, 1));
      await assert.rejects(() => verify(api, 1));
      const revoked = await revocations(api, 1, BASE);
      assert.equal(Object.keys(revoked).length, Object.keys(policy.reviewers).length);
      assert(!api.statuses.some(s => s.state === 'success'));
      // Full recovery is possible using new attestations, not clearing history.
      api.comments.push(...comments().map((c, i) => ({...c, id: i + 20,
        created_at: '2026-10-13T00:00:01Z', updated_at: '2026-10-13T00:00:01Z'})));
      await verify(api, 1);
      assert.equal(api.statuses.at(-1).state, 'success');
    });
  }
}
test('head-only latch is promoted with original epoch and stays sticky despite pending/failure history', async () => {
  const api = eventAPI(), call = api.call.bind(api), pages = api.pages.bind(api);
  const records = [{state: 'failure', context: policy.context, description: 'revoked-pr-1:all:1', created_at: '2026-10-12T00:00:00Z'}];
  api.pages = async path => path === `commits/${HEAD}/statuses` ? records : pages(path);
  api.call = async (path, method, data) => {
    if (method === 'POST' && path === `statuses/${HEAD}`) records.push({...data, created_at: '2026-10-12T00:00:00Z'});
    return call(path, method, data);
  };
  await assert.rejects(() => verify(api, 1));
  await assert.rejects(() => verify(api, 1));
  assert.equal(api.records.length, 1);
  assert.deepEqual(Object.keys(await revocations(api, 1, BASE)), ['owner']);
});

for (const mode of ['forceRevert', 'fastForward']) {
  test(`head-only latch cannot be hidden by ${mode} before anchor recovery`, async () => {
    const api = eventAPI(), call = api.call.bind(api), pages = api.pages.bind(api);
    const C = 'c'.repeat(40);
    let moved = false, failAnchor = true;
    const headARecords = [];
    api.call = async (path, method, data) => {
      if (method === 'POST' && path === `statuses/${policy.revocationAnchor}` && failAnchor) throw new Error('anchor unavailable');
      if (method === 'POST' && path === `statuses/${HEAD}`) headARecords.push({...data, created_at: '2026-10-12T00:00:00Z'});
      const result = await call(path, method, data);
      if (moved && path === 'pulls/1') return {...result, head: {sha: C}};
      if (moved && path.startsWith('contents/') && path.endsWith(C)) return {sha: C};
      if (moved && path.startsWith('actions/runs/')) return {...result, head_sha: C};
      return result;
    };
    api.pages = async path => {
      if (path === `commits/${HEAD}/statuses`) return headARecords;
      if (path === `commits/${C}/statuses`) return [];
      if (path === 'issues/1/events') return moved && mode === 'forceRevert' ?
        [{event: 'head_ref_force_pushed', created_at: '2026-10-12T00:00:01Z'}] : [];
      const result = await pages(path);
      if (moved && path === 'pulls/1/commits') return mode === 'fastForward' ? [...result, {...result[0], sha: C}] : [{...result[0], sha: C}];
      if (moved && path.startsWith('actions/runs?')) return result.map(r => ({...r, head_sha: C}));
      if (moved && path.includes('/jobs')) return result.map(j => ({...j, head_sha: C}));
      return result;
    };
    await assert.rejects(() => revokeEvent(api, deletion(marker({head: BASE}))));
    moved = true; failAnchor = false;
    api.comments.splice(0, api.comments.length, ...comments().map(c => ({...c, body: body(marker({lens: parse(c.body).lens, head: C}))})));
    await assert.rejects(() => verify(api, 1));
    assert(!api.statuses.some(s => s.state === 'success'));
    api.comments.push(...comments().map((c, i) => ({...c, id: i + 20, created_at: '2026-10-13T00:00:00Z',
      updated_at: '2026-10-13T00:00:00Z', body: body(marker({lens: parse(c.body).lens, head: C}))})));
    await verify(api, 1);
    assert.equal(api.statuses.at(-1).state, 'success');
  });
}
test('force-push event read failure and invalid epoch fail closed', async () => {
  for (const invalid of [false, true]) {
    const api = fakeAPI(), pages = api.pages.bind(api);
    api.pages = async path => {
      if (path === 'issues/1/events') {
        if (!invalid) throw new Error('events unavailable');
        return [{event: 'head_ref_force_pushed', created_at: 'bad'}];
      }
      return pages(path);
    };
    await assert.rejects(() => verify(api, 1));
    assert.equal(api.statuses.at(-1).state, 'failure');
  }
});

const {targets, API, RateLimitError} = require('./verify.cjs');
const openPR = (number, sha = 'c'.repeat(40), extra = {}) => ({number, draft: false, state: 'open', base: {ref: 'main'}, head: {sha}, ...extra});
function listAPI(list) {
  const calls = [];
  return {calls, async call(path) { calls.push(path); const n = Number(path.split('/')[1]); return list.find(p => p.number === n) || {...openPR(n), state: 'closed'}; },
    async pages(path) { calls.push(path); return list; }};
}
test('a comment or dispatch sweeps only its own PR and skips closed, draft or other-base PRs', async () => {
  const api = listAPI([openPR(5), openPR(6, 'd'.repeat(40), {draft: true}), openPR(7, 'e'.repeat(40), {base: {ref: 'dev'}})]);
  assert.deepEqual(await targets(api, 'issue_comment', {issue: {number: 5}}), [5]);
  assert.deepEqual(await targets(api, 'workflow_dispatch', {inputs: {pr_number: '5'}}), [5]);
  for (const number of [6, 7, 8]) assert.deepEqual(await targets(api, 'issue_comment', {issue: {number}}), []);
  assert.deepEqual(api.calls.filter(path => path.startsWith('pulls?')), []);
  await assert.rejects(() => targets(api, 'workflow_dispatch', {inputs: {pr_number: 'x'}}), /invalid PR number/);
});
test('a CI run sweeps the PRs it names or whose head it ran, never the rest', async () => {
  const api = listAPI([openPR(1, 'a'.repeat(40)), openPR(2, 'b'.repeat(40)), openPR(3, 'c'.repeat(40))]);
  assert.deepEqual(await targets(api, 'workflow_run', {workflow_run: {pull_requests: [{number: 1}], head_sha: 'f'.repeat(40)}}), [1]);
  assert.deepEqual(await targets(api, 'workflow_run', {workflow_run: {pull_requests: [], head_sha: 'b'.repeat(40)}}), [2]);
  assert.deepEqual(await targets(api, 'workflow_run', {workflow_run: {head_sha: 'f'.repeat(40)}}), []);
});
test('a completed CI run sweeps only when it is not a main-push run', async () => {
  const api = listAPI([openPR(1, 'a'.repeat(40)), openPR(2, 'b'.repeat(40))]);
  // Main-push CI completions are covered by the gate's own push sweep.
  assert.deepEqual(await targets(api, 'workflow_run', {workflow_run: {event: 'push', pull_requests: [{number: 1}], head_sha: 'a'.repeat(40)}}), []);
  // Manually dispatched CI carries no pull_requests; the head SHA names the PR.
  assert.deepEqual(await targets(api, 'workflow_run', {workflow_run: {event: 'workflow_dispatch', pull_requests: [], head_sha: 'b'.repeat(40)}}), [2]);
});
test('a push to main sweeps every open ready PR', async () => {
  const api = listAPI([openPR(1), openPR(2, 'd'.repeat(40), {draft: true}), openPR(3)]);
  assert.deepEqual(await targets(api, 'push', {}), [1, 3]);
});
test('one sweep reads the anchor ledger once however many PRs it covers', async () => {
  const api = fakeAPI(), pages = api.pages.bind(api), sweep = {};
  let ledgerReads = 0;
  api.pages = async path => { if (path === `commits/${policy.revocationAnchor}/statuses`) ledgerReads++; return pages(path); };
  await verify(api, 1, sweep); await verify(api, 1, sweep);
  assert.equal(ledgerReads, 3); // one shared read plus one live final re-check per PR
});
test('a failed shared ledger read is not remembered for the next PR', async () => {
  const api = fakeAPI(), pages = api.pages.bind(api), sweep = {};
  let fail = true;
  api.pages = async path => { if (fail && path === `commits/${policy.revocationAnchor}/statuses`) { fail = false; throw new Error('ledger unavailable'); } return pages(path); };
  await assert.rejects(() => verify(api, 1, sweep), /ledger unavailable/);
  await verify(api, 1, sweep);
});
function fetchStub(response) {
  const original = globalThis.fetch;
  globalThis.fetch = async () => response;
  return () => { globalThis.fetch = original; };
}
const reply = (status, headers, body) => ({ok: status < 300, status, headers: new Headers(headers), text: async () => body, json: async () => JSON.parse(body)});
const limits = [
  [403, {'x-ratelimit-remaining': '0', 'x-ratelimit-reset': '1791747209'}, 'Forbidden'],
  [429, {}, 'slow down'],
  [403, {'retry-after': '30'}, 'try later'],
  [403, {}, 'You have exceeded a secondary rate limit']
];
for (const [status, headers, message] of limits) {
  test(`HTTP ${status} with exhaustion evidence (${Object.keys(headers)[0] || message}) is a rate limit`, async () => {
    const restore = fetchStub(reply(status, headers, JSON.stringify({message})));
    try {
      await assert.rejects(() => new API('o/r', 't').call('pulls/1'), error => {
        assert.ok(error instanceof RateLimitError);
        assert.match(error.message, new RegExp(`^GitHub API ${status} \\(rate limit\\): pulls/1; remaining ${headers['x-ratelimit-remaining'] ?? 'unknown'}, resets ${headers['x-ratelimit-reset'] ? '2026-10-11T' : 'unknown'}`));
        assert.ok(error.message.includes(`${message}; stopped without writing statuses`));
        return true;
      });
    } finally { restore(); }
  });
}
for (const [status, headers, message] of [[403, {'x-ratelimit-remaining': '4999'}, 'Resource not accessible by integration'],
  [403, {}, 'Resource protected by organization SAML enforcement'], [500, {}, 'oops']]) {
  test(`HTTP ${status} without exhaustion evidence (${message}) is an ordinary failure`, async () => {
    const restore = fetchStub(reply(status, headers, JSON.stringify({message})));
    try { await assert.rejects(() => new API('o/r', 't').call('pulls/1'), error => !(error instanceof RateLimitError) && error.message === `GitHub API ${status}: pulls/1`); }
    finally { restore(); }
  });
}
test('a permission 403 still writes the fail-closed failure status', async () => {
  const api = fakeAPI(), pages = api.pages.bind(api);
  api.pages = async path => { if (path === 'issues/1/comments') throw new Error('GitHub API 403: issues/1/comments'); return pages(path); };
  await assert.rejects(() => verify(api, 1), /GitHub API 403/);
  assert.deepEqual(api.statuses.map(s => s.state), ['pending', 'failure']);
});
test('other HTTP errors keep their short message, so a 404 stays recognizable', async () => {
  const restore = fetchStub(reply(404, {}, '{}'));
  try { await assert.rejects(() => new API('o/r', 't').call('contents/x'), error => !(error instanceof RateLimitError) && error.message === 'GitHub API 404: contents/x'); }
  finally { restore(); }
});
test('a rate limit stops verification without writing a failure status', async () => {
  const api = fakeAPI(), pages = api.pages.bind(api);
  api.pages = async path => { if (path === 'issues/1/comments') throw new RateLimitError('GitHub API 403: out of quota'); return pages(path); };
  await assert.rejects(() => verify(api, 1), RateLimitError);
  assert.deepEqual(api.statuses.map(s => s.state), ['pending']);
});
test('a failure status that cannot be written does not hide the original reason', async () => {
  const api = fakeAPI({behind: true}), call = api.call.bind(api);
  api.call = async (path, method, data) => { if (method === 'POST' && data.state === 'failure') throw new Error('GitHub API 500: statuses'); return call(path, method, data); };
  await assert.rejects(() => verify(api, 1), /head is not ahead of its base.*failure status could not be written.*500/);
});

test('a spent quota during the revocation latch keeps its reset details and still tries both latches', async () => {
  const api = eventAPI(), call = api.call.bind(api), attempts = [];
  api.call = async (path, method, data) => {
    if (method === 'POST') { attempts.push(data.context); throw new RateLimitError('GitHub API 429 (rate limit): statuses/x; remaining 0, resets 2026-10-12T01:00:00.000Z'); }
    return call(path, method, data);
  };
  await assert.rejects(() => revokeEvent(api, deletion(marker({head: BASE}))), error => error instanceof RateLimitError && /resets 2026-10-12T01:00:00/.test(error.message));
  assert.equal(attempts.length, 2);
});
test('other latch write failures still fail loudly and now name the cause', async () => {
  const api = eventAPI(), call = api.call.bind(api);
  api.call = async (path, method, data) => { if (method === 'POST') throw new Error('GitHub API 500: statuses'); return call(path, method, data); };
  await assert.rejects(() => revokeEvent(api, deletion(marker({head: BASE}))), error => !(error instanceof RateLimitError) &&
    /^revocation latch write failed; retry event after API recovery: GitHub API 500: statuses \| GitHub API 500: statuses$/.test(error.message));
});

// The lane registry serializes runs the YAML concurrency lanes cannot: fork
// CI sweeps (head-sha lane) against comment revocations (PR lane) (#434).
test('lane overlap: only a newer live lane sharing a PR defers this run', async () => {
  process.env.GITHUB_RUN_ID = '41';
  const now = new Date().toISOString();
  const lane = (id, prs, extra = {}) => ({context: 'panel/lane', state: 'pending',
    description: `run-${id}:pr-${prs}`, created_at: now, ...extra});
  const api = records => ({pages: async () => records});
  assert.equal(await overlappingNewerLane(api([lane(99, '1')]), [1]), true);
  assert.equal(await overlappingNewerLane(api([lane(99, '3,1')]), [1]), true);
  assert.equal(await overlappingNewerLane(api([lane(99, 'all')]), [1]), true);
  assert.equal(await overlappingNewerLane(api([lane(99, '2')]), [1]), false);
  assert.equal(await overlappingNewerLane(api([lane(40, '1')]), [1]), false);
  assert.equal(await overlappingNewerLane(api([lane(41, '1')]), [1]), false);
  assert.equal(await overlappingNewerLane(api([lane(99, '1', {state: 'success'})]), [1]), false);
  assert.equal(await overlappingNewerLane(api([lane(99, '1', {created_at: '2020-01-01T00:00:00Z'})]), [1]), false);
  assert.equal(await overlappingNewerLane(api([{...lane(99, '1'), context: 'panel/revoked/pr-1'}]), [1]), false);
  assert.equal(await overlappingNewerLane(api([lane(99, '1')]), []), false);
});
test('lane overlap: the newest record per lane key wins, malformed fails closed', async () => {
  process.env.GITHUB_RUN_ID = '41';
  const now = new Date().toISOString();
  const lane = state => ({context: 'panel/lane', state, description: 'run-99:pr-1', created_at: now});
  // The API lists statuses newest first: the resolved record leads.
  const api = {pages: async () => [lane('success'), lane('pending')]};
  assert.equal(await overlappingNewerLane(api, [1]), false);
  const bad = {pages: async () => [{context: 'panel/lane', state: 'pending', description: 'garbage', created_at: now}]};
  await assert.rejects(() => overlappingNewerLane(bad, [1]), /invalid lane record/);
});
test('postLane registers the resolved targets and closeLane resolves the same lane', async () => {
  process.env.GITHUB_RUN_ID = '41';
  const statuses = [];
  const api = {call: async (path, method, data) => { statuses.push(data); return data; }};
  const lane = await postLane(api, [1, 2], 'issue_comment');
  assert.equal(lane, 'run-41:pr-1,2');
  await closeLane(api, lane, true);
  assert.deepEqual(statuses.map(s => [s.state, s.context, s.description]),
    [['pending', 'panel/lane', 'run-41:pr-1,2'], ['success', 'panel/lane', 'run-41:pr-1,2']]);
  assert.equal(await postLane(api, [1], 'push'), 'run-41:pr-all');
  assert.equal(await postLane(api, [], 'issue_comment'), null);
  await closeLane(api, null, true);
  assert.equal(statuses.length, 3);
});
test('lane writes fail open with a log line, but never hide a quota error', async () => {
  process.env.GITHUB_RUN_ID = '41';
  const boom = {call: async () => { throw new Error('boom'); }};
  assert.equal(await postLane(boom, [1], 'issue_comment'), null);
  await closeLane(boom, 'run-41:pr-1', true);
  const quota = {call: async () => { throw new RateLimitError('spent'); }};
  await assert.rejects(() => postLane(quota, [1], 'issue_comment'));
  await assert.rejects(() => closeLane(quota, 'run-41:pr-1', true));
});
