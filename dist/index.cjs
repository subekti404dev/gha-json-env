'use strict';

/**
 * GitHub Action: Fetch & Flatten Remote ENV (Node 20)
 * - Inputs:
 *   - url (required)
 *   - style: snake (default), camel, dot
 *   - token: optional bearer token
 * - Output:
 *   - Writes KEY=VALUE lines to GITHUB_ENV
 */

const fs = require('fs');
const path = require('path');
const { URL } = require('url');

// Helpers to read inputs in a runtime-agnostic way
function getInput(name, { required = false, defaultValue = '' } = {}) {
  // GitHub Actions provides getInput via actions/core, but to avoid dependency,
  // read from environment following INPUT_<NAME> convention or fallback to process.env[name]
  const envVar = `INPUT_${name.toUpperCase()}`;
  let val = process.env[envVar] ?? process.env[name] ?? '';
  if (!val && defaultValue) val = defaultValue;
  if (required && !val) {
    throw new Error(`Missing required input: ${name}`);
  }
  return String(val).trim();
}

function assertValidUrl(raw) {
  try {
    const u = new URL(raw);
    if (!u.protocol || !/^https?:$/.test(u.protocol)) {
      throw new Error('URL must start with http:// or https://');
    }
    return u.toString();
  } catch (e) {
    throw new Error(`Invalid URL: ${raw}`);
  }
}

// Flattening logic
function splitTokens(seg) {
  // normalize separators to underscore, split, and filter empties
  return seg.replace(/[.\-]/g, '_').split('_').filter(Boolean).map(t => t.toLowerCase());
}

function joinSnake(tokens) {
  return tokens.join('_');
}
function joinDot(tokens) {
  return tokens.join('.');
}
function joinCamel(tokens) {
  if (tokens.length === 0) return '';
  const [first, ...rest] = tokens;
  return first.toLowerCase() + rest.map(t => t.charAt(0).toUpperCase() + t.slice(1).toLowerCase()).join('');
}

function joinPath(segments, style) {
  // segments is array of raw segments like ['database','host'] or ['items','0','name']
  const tokens = segments.flatMap(splitTokens);
  switch (style) {
    case 'camel':
      return joinCamel(tokens);
    case 'dot':
      return joinDot(tokens);
    case 'snake':
    default:
      return joinSnake(tokens);
  }
}

function flatten(obj, style, prefixSegments = [], out = []) {
  if (obj !== null && typeof obj === 'object' && !Array.isArray(obj)) {
    for (const [k, v] of Object.entries(obj)) {
      flatten(v, style, [...prefixSegments, k], out);
    }
  } else if (Array.isArray(obj)) {
    obj.forEach((v, i) => flatten(v, style, [...prefixSegments, String(i)], out));
  } else {
    const key = joinPath(prefixSegments, style);
    out.push([key, String(obj)]);
  }
  return out;
}

async function fetchJson(url, token) {
  const headers = { 'Accept': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const res = await fetch(url, { headers, redirect: 'follow' });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Failed to fetch JSON (${res.status} ${res.statusText}): ${body.slice(0, 200)}`);
  }
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Error('Invalid JSON format');
  }
}

async function main() {
  const url = assertValidUrl(getInput('url', { required: true }));
  let style = getInput('style', { defaultValue: 'snake' }).toLowerCase();
  const token = getInput('token', { defaultValue: '' });

  if (!['snake', 'camel', 'dot'].includes(style)) {
    throw new Error(`Invalid style '${style}'. Allowed: snake, camel, dot`);
  }

  // Mask URL in logs
  console.log('📥 Fetching env.json from ***');
  const json = await fetchJson(url, token);
  console.log('🔍 Validating JSON format');

  console.log(`🔧 Flattening with style: ${style}`);
  const pairs = flatten(json, style);

  const envPath = process.env.GITHUB_ENV;
  if (!envPath) {
    throw new Error('GITHUB_ENV is not set. This action must run in GitHub Actions environment.');
  }

  const lines = pairs.map(([k, v]) => {
    console.log(`Setting env: ${k}`);
    return `${k}=${v}`;
  });

  fs.appendFileSync(envPath, lines.join('\n') + '\n', { encoding: 'utf8' });
  console.log('✅ Done.');
}

// Node 18+ provides global fetch. For Node 20 runtime it exists. Fallback guard:
if (typeof fetch !== 'function') {
  global.fetch = (...args) => import('node-fetch').then(({default: f}) => f(...args));
}

main().catch(err => {
  console.error(`❌ ${err.message}`);
  process.exit(1);
});