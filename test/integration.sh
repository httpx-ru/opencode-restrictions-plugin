#!/usr/bin/env bash
# Integration tests for @httpx-ru/opencode-restrictions-plugin
# Requires: BOTHUB_API_KEY (for model-based tests), opencode CLI installed
set -euo pipefail

PASS=0
FAIL=0
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_PATH="$ROOT_DIR/dist/index.js"
ALLOWED_MODEL="bothub/deepseek-v4-flash"
DENIED_MODEL="anthropic/claude-sonnet-4-6"

info()  { printf "  ℹ️  %s\n" "$1"; }
pass()  { printf "  ✅ %s\n" "$1"; ((PASS++)); }
fail()  { printf "  ❌ %s\n" "$1"; ((FAIL++)); }

# Cross-platform timeout for opencode run
if command -v timeout &>/dev/null; then
  TIMEOUT="timeout"
elif command -v gtimeout &>/dev/null; then
  TIMEOUT="gtimeout"
else
  # perl alarm fallback
  TIMEOUT="perl -e"
fi

open_with_timeout() {
  local secs=$1; shift
  if [ "$TIMEOUT" = "perl -e" ]; then
    perl -e "alarm $secs; exec @ARGV" -- "$@" 2>&1
  else
    $TIMEOUT "$secs" "$@" 2>&1
  fi
}

setup_testdir() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.opencode/agents" "$dir/.opencode/skills/test-skill"

  cat > "$dir/.opencode/restrict.json" <<RESTRICT
{
  "agents": { "allowed": ["build", "plan", "general", "explore", "project-test-agent"] },
  "models": { "allowed": ["$ALLOWED_MODEL"] },
  "skills": { "allowed": ["test-skill"] }
}
RESTRICT

  cat > "$dir/.opencode/agents/project-test-agent.md" <<AGENT
---
description: Test agent for integration tests
mode: subagent
---
You are a test agent.
AGENT

  cat > "$dir/.opencode/skills/test-skill/SKILL.md" <<SKILL
---
description: Test skill for integration tests
---
# Test Skill
SKILL

  cat > "$dir/opencode.json" <<OPCODE
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "$ALLOWED_MODEL",
  "default_agent": "plan",
  "plugin": ["$PLUGIN_PATH"],
  "provider": {
    "bothub": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "BotHub",
      "options": { "baseURL": "https://openai.bothub.ru/v1" },
      "env": ["BOTHUB_API_KEY"],
      "models": {
        "deepseek-v4-flash": { "name": "DeepSeek V4 Flash" }
      }
    }
  }
}
OPCODE

  echo "$dir"
}

cleanup_testdir() { rm -rf "$1"; }

# ── Test: plugin loads without restrict.json ──
test_no_config() {
  info "Test: no restrict.json — plugin should not crash"
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.opencode/agents"
  cat > "$dir/opencode.json" <<OPCODE
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "$ALLOWED_MODEL",
  "default_agent": "plan",
  "plugin": ["$PLUGIN_PATH"],
  "provider": {
    "bothub": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "BotHub",
      "options": { "baseURL": "https://openai.bothub.ru/v1" },
      "env": ["BOTHUB_API_KEY"],
      "models": {
        "deepseek-v4-flash": { "name": "DeepSeek V4 Flash" }
      }
    }
  }
}
OPCODE
  if output=$(cd "$dir" && open_with_timeout 20 opencode run "respond with just: ok" 2>&1); then
    pass "no config: opencode ran successfully"
  else
    fail "no config: opencode failed — $(echo "$output" | head -3)"
  fi
  cleanup_testdir "$dir"
}

# ── Test: restricted model is blocked ──
test_denied_model() {
  info "Test: denied model should fail"
  local dir
  dir=$(setup_testdir)
  if output=$(cd "$dir" && open_with_timeout 45 opencode run "respond with just: ok" --model "$DENIED_MODEL" 2>&1); then
    fail "denied model: should have failed but succeeded"
  else
    pass "denied model: blocked as expected"
  fi
  cleanup_testdir "$dir"
}

# ── Test: allowed model works ──
test_allowed_model() {
  info "Test: allowed model should succeed"
  local dir
  dir=$(setup_testdir)
  if output=$(cd "$dir" && open_with_timeout 45 opencode run "respond with just: ok" 2>&1); then
    pass "allowed model: works"
  else
    fail "allowed model: failed — $(echo "$output" | head -3)"
  fi
  cleanup_testdir "$dir"
}

# ── Test: empty models.allowed denies all models ──
test_empty_models() {
  info "Test: empty models.allowed — all models denied"
  local dir
  dir=$(setup_testdir)
  cat > "$dir/.opencode/restrict.json" <<RESTRICT
{ "models": { "allowed": [] } }
RESTRICT
  cat > "$dir/opencode.json" <<OPCODE
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "$ALLOWED_MODEL",
  "default_agent": "plan",
  "plugin": ["$PLUGIN_PATH"],
  "provider": {
    "bothub": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "BotHub",
      "options": { "baseURL": "https://openai.bothub.ru/v1" },
      "env": ["BOTHUB_API_KEY"],
      "models": {
        "deepseek-v4-flash": { "name": "DeepSeek V4 Flash" }
      }
    }
  }
}
OPCODE
  if output=$(cd "$dir" && open_with_timeout 20 opencode run "respond with just: ok" 2>&1); then
    fail "empty models.allowed: should have failed"
  else
    pass "empty models.allowed: all models denied"
  fi
  cleanup_testdir "$dir"
}

echo ""
echo "═══ @httpx-ru/opencode-restrictions-plugin integration tests ═══"
echo ""

if [ -z "${BOTHUB_API_KEY:-}" ]; then
  echo "  ⚠️  BOTHUB_API_KEY not set — all tests skipped"
  echo ""
  exit 0
fi

echo "--- test_no_config ---" && test_no_config || true
echo "--- test_allowed_model ---" && test_allowed_model || true
echo "--- test_denied_model ---" && test_denied_model || true
echo "--- test_empty_models ---" && test_empty_models || true

echo ""
echo "═══ Results: $PASS passed, $FAIL failed ═══"
echo ""

exit $FAIL