# @httpx-ru/opencode-restrictions-plugin

[![npm version](https://img.shields.io/npm/v/@httpx-ru/opencode-restrictions-plugin)](https://www.npmjs.com/package/@httpx-ru/opencode-restrictions-plugin)
[![License: MIT](https://img.shields.io/npm/l/@httpx-ru/opencode-restrictions-plugin)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/httpx-ru/opencode-restrictions-plugin/actions/workflows/check.yml/badge.svg)](https://github.com/httpx-ru/opencode-restrictions-plugin/actions/workflows/check.yml)

Opencode plugin for restricting agents, models, and skills via a whitelist.

## Installation

```bash
npm install @httpx-ru/opencode-restrictions-plugin
```

## Usage

Add the plugin with a pinned version to your project's `opencode.json`:

```jsonc
// opencode.json
{
  "plugin": ["@httpx-ru/opencode-restrictions-plugin@0.1.3"]
}
```

Pinning the exact version prevents issues caused by opencode's plugin cache — it does not automatically check npm for updates on every launch. Using `@latest` or omitting the version entirely may cause the plugin to stall on an older cached version even after a newer one is published.

After changing the pinned version, clear the cache before launching:

```bash
rm -rf ~/.cache/opencode/packages/@httpx-ru
```

Create `.opencode/restrict.json` with your whitelist rules:

```jsonc
// .opencode/restrict.json
{
  "agents": {
    "allowed": ["build", "plan", "code-reviewer"]
  },
  "models": {
    "allowed": ["bothub/deepseek-v4-flash"]
  },
  "skills": {
    "allowed": ["code-review"]
  }
}
```

## Behavior

| Section | Missing | `allowed: []` | `allowed: [...]` |
|---------|---------|---------------|------------------|
| `agents` | no restriction | disables **all** file-based agents | disables all except listed |
| `models` | no restriction | denies **all** models | allows only listed |
| `skills` | no restriction | denies **all** skills | allows only listed |

## How it works

| Resource | Mechanism | Enforcement |
|----------|-----------|-------------|
| **Agents** | `cfg.agent[name] = { disable: true }` via `config()` hook | hard |
| **Models** | `enabled_providers` + `provider.whitelist` | hard |
| **Skills** | `permission.skill` deny-rules on all agents via `config()` hook | hard |

## Requirements

- opencode >= 1.17
- Node.js >= 22

## Development

```bash
git clone https://github.com/httpx-ru/opencode-restrictions-plugin
cd opencode-restrictions-plugin
npm install
npm run build
```

### Integration tests

```bash
BOTHUB_API_KEY=your-key bash test/integration.sh
```

## License

MIT