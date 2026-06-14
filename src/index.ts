import type { Plugin, Config } from "@opencode-ai/plugin"
import { readFileSync, readdirSync } from "node:fs"
import { join } from "node:path"
import { homedir } from "node:os"

interface RestrictConfig {
  agents?: { allowed?: string[] }
  models?: { allowed?: string[] }
  skills?: { allowed?: string[] }
}

function readConfig(directory: string, worktree: string): RestrictConfig | null {
  for (const root of [directory, worktree]) {
    try {
      const content = readFileSync(join(root, ".opencode", "restrict.json"), "utf-8")
      return JSON.parse(content) as RestrictConfig
    } catch { /* not found or invalid */ }
  }
  return null
}

function scanAgentNames(...dirs: string[]): string[] {
  const found: string[] = []
  for (const dir of dirs) {
    try {
      for (const file of readdirSync(dir)) {
        if (file.endsWith(".md")) {
          found.push(file.replace(/\.md$/, ""))
        }
      }
    } catch { /* dir doesn't exist */ }
  }
  return found
}

function parseModelKey(key: string): { provider: string; model: string } | null {
  const idx = key.indexOf("/")
  if (idx === -1) return null
  return { provider: key.slice(0, idx), model: key.slice(idx + 1) }
}

const plugin: Plugin = async ({ directory, worktree }) => {
  const cfg = readConfig(directory, worktree)
  if (!cfg) return {}

  const hasAgents = "agents" in cfg
  const hasModels = "models" in cfg
  const hasSkills = "skills" in cfg

  const agentAllowed = cfg.agents?.allowed
  const modelAllowed = cfg.models?.allowed
  const skillAllowed = cfg.skills?.allowed

  const HOME = homedir()

  // ── Agent whitelist ──
  const agentsToDisable: string[] = []
  if (hasAgents) {
    const agentDirs = [
      join(HOME, ".config", "opencode", "agent"),
      join(HOME, ".config", "opencode", "agents"),
      join(directory, ".opencode", "agents"),
      join(directory, ".opencode", "agent"),
    ]

    if (agentAllowed && agentAllowed.length > 0) {
      const allow = new Set(agentAllowed)
      const all = [...new Set(scanAgentNames(...agentDirs))]
      agentsToDisable.push(...all.filter((name) => !allow.has(name)))
    } else {
      const all = [...new Set(scanAgentNames(...agentDirs))]
      agentsToDisable.push(...all)
    }
  }

  // ── Model whitelist ──
  const modelProviders = new Set<string>()
  const modelsByProvider: Record<string, string[]> = {}
  if (hasModels && modelAllowed) {
    for (const key of modelAllowed) {
      const parsed = parseModelKey(key)
      if (parsed) {
        modelProviders.add(parsed.provider)
        modelsByProvider[parsed.provider] ??= []
        modelsByProvider[parsed.provider].push(parsed.model)
      }
    }
  }

  return {
    config: async (out: Config) => {
      // ── Agents ──
      if (hasAgents && agentsToDisable.length > 0) {
        out.agent ??= {}
        for (const name of agentsToDisable) {
          out.agent[name] = { disable: true }
        }
      }

      // ── Models ──
      if (hasModels) {
        const c = out as Record<string, unknown>

        if (modelAllowed && modelAllowed.length > 0) {
          c["enabled_providers"] = [...modelProviders]

          for (const [provider, models] of Object.entries(modelsByProvider)) {
            const p = ((c["provider"] ??= {}) as Record<string, Record<string, unknown>>)
            const pc = (p[provider] ??= {}) as Record<string, unknown>
            pc["whitelist"] = models
          }
        } else {
          c["enabled_providers"] = []
          c["model"] = undefined
          c["small_model"] = undefined
        }
      }

      // ── Skills ──
      if (hasSkills) {
        const c = out as Record<string, unknown>
        const s = ((c["skills"] ??= {}) as Record<string, unknown>)
        s["paths"] = [join(directory, ".opencode", "skills")]

        for (const agentCfg of Object.values(out.agent ?? {})) {
          if (!agentCfg || typeof agentCfg !== "object") continue
          const a = agentCfg as Record<string, unknown>
          const p = ((a["permission"] ??= {}) as Record<string, unknown>)
          const skillRules: Record<string, string> = {}
          if (skillAllowed && skillAllowed.length > 0) {
            for (const name of skillAllowed) skillRules[name] = "allow"
          }
          skillRules["*"] = "deny"
          p["skill"] = skillRules
        }
      }
    },

    "experimental.chat.system.transform": async (_input, output) => {
      if (agentsToDisable.length > 0) {
        const allowedList = agentAllowed?.join(", ") ?? ""
        output.system.push(
          `RESTRICTED AGENTS: ${agentsToDisable.join(", ")} are disabled. Only allowed: ${allowedList}`
        )
      }
      if (hasSkills) {
        output.system.push(
          skillAllowed && skillAllowed.length > 0
            ? `RESTRICTED SKILLS: only allowed skills: ${skillAllowed.join(", ")}`
            : "RESTRICTED SKILLS: no skills are allowed"
        )
      }
      if (hasModels) {
        output.system.push(
          modelAllowed && modelAllowed.length > 0
            ? `RESTRICTED MODELS: only allowed models: ${modelAllowed.join(", ")}`
            : "RESTRICTED MODELS: no models are allowed"
        )
      }
    },
  }
}

export default plugin