// Browser-level smoke test — catches client-side React crashes that a curl 200 misses.
// Loads key Ivory pages headlessly, FAILS on any console error, page error, or the
// React error boundary ("Something went wrong"). This is the gate before claiming a
// frontend change "done" (see system/rules non-negotiable #14 + system/meta/verification.md).
//
// Run on Paul's PC (has node + reaches the rig over Tailscale):
//   node le-roux-repo/script/browser_smoke.mjs
//   IVORY_BASE=http://100.73.38.21:3000 PAGES=/diary,/patients node ... (overrides)
import { chromium } from 'playwright';

const BASE  = process.env.IVORY_BASE || 'http://100.73.38.21:3000';      // rig over Tailscale
const CREDS = { username: process.env.IVORY_USER || 'reception',
                password: process.env.IVORY_PASS || 'Jbxs8sMFEmWNLs' };  // remote needs auth
const PAGES = (process.env.PAGES || '/dashboard,/diary,/patients,/procedure-codes').split(',');

const browser = await chromium.launch();
let failed = 0;
for (const path of PAGES) {
  const ctx = await browser.newContext({ httpCredentials: CREDS, ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  const errs = [];
  page.on('console', m => { if (m.type() === 'error') errs.push(m.text().slice(0, 200)); });
  page.on('pageerror', e => errs.push('PAGEERROR: ' + e.message.slice(0, 200)));
  let status = 0, crashed = false;
  try {
    const resp = await page.goto(BASE + path, { waitUntil: 'networkidle', timeout: 25000 });
    status = resp ? resp.status() : 0;
    await page.waitForTimeout(1500);
    const body = (await page.textContent('body')) || '';
    crashed = /Something went wrong|An unexpected error occurred/.test(body);
  } catch (e) { errs.push('GOTO: ' + e.message.slice(0, 200)); }
  const ok = status === 200 && !crashed && errs.length === 0;
  console.log(`${ok ? 'PASS ok ' : 'FAIL x  '} ${path.padEnd(18)} status=${status} crashed=${crashed} consoleErrors=${errs.length}`);
  errs.slice(0, 4).forEach(e => console.log('       - ' + e));
  if (!ok) failed++;
  await ctx.close();
}
await browser.close();
console.log(failed ? `\n${failed} page(s) FAILED` : `\nAll ${PAGES.length} pages OK`);
process.exit(failed ? 1 : 0);
