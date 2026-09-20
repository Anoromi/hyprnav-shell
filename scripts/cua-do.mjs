#!/usr/bin/env node
// Run one JavaScript snippet through the cua MCP server against the lab
// compositor, for scripted demos (clicks, typing, screenshots of windows).
//   scripts/cua-do.mjs 'const a = await cua.getApp("zen-beta"); await a.click([100,100]);'
// Environment must already be the lab's (use `lab.py exec`).
import {spawn} from 'node:child_process';
import readline from 'node:readline';
const code = process.argv.slice(2).join(' ');
const launcher = process.env.CUA_LAUNCHER ?? `${process.env.HOME}/code/experiments/hypr-use/mcp/hypr-use-mcp-inherit`;
const child = spawn(launcher, [], {stdio: ['pipe', 'pipe', 'inherit'], env: {...process.env, HYPR_USE_AGENT_ID: process.env.CUA_AGENT_ID ?? 'cua-demo-driver', HYPR_USE_AGENT_LABEL: process.env.CUA_AGENT_LABEL ?? 'demo driver', HYPR_USE_NO_HYPRNAV: process.env.CUA_REGISTER === '1' ? '0' : '1'}});
let id = 0; const pending = new Map();
readline.createInterface({input: child.stdout}).on('line', line => { let m; try { m = JSON.parse(line); } catch { return; } const p = pending.get(m.id); if (p) { pending.delete(m.id); p(m); } });
const rpc = (method, params) => new Promise(resolve => { pending.set(++id, resolve); child.stdin.write(JSON.stringify({jsonrpc: '2.0', id, method, params}) + '\n'); });
await rpc('initialize', {protocolVersion: '2025-06-18', capabilities: {}, clientInfo: {name: 'cua-do', version: '0'}});
const r = await rpc('tools/call', {name: 'js', arguments: {code, timeout_ms: Number(process.env.CUA_TIMEOUT_MS ?? 60000)}});
for (const c of r.result?.content ?? []) { if (c.type === 'text') console.log(c.text); else if (c.type === 'image') console.log(`[image ${c.data?.length ?? 0} b64 chars]`); }
if (r.result?.isError) process.exitCode = 1;
if (process.env.CUA_FINISH !== '0') await rpc('tools/call', {name: 'turn_ended', arguments: {hook_event_name: 'Stop', session_id: 'demo', turn_id: String(Date.now())}});
child.stdin.end();
