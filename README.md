# jdb-debugger

An [Agent Skill](https://agentskills.io/specification) that teaches AI agents to debug Java applications in real time using JDB — the command-line debugger shipped with every JDK.

## What This Skill Does

When activated, this skill enables AI agents to:

- **Launch** a Java application under JDB for step-by-step debugging
- **Attach** to a running JVM with JDWP enabled (local or remote)
- **Set breakpoints** at lines, methods, constructors, or on exceptions
- **Step through code** — step into, step over, step up
- **Inspect variables** — locals, fields, expressions, full object dumps
- **Analyze threads** — thread dumps, deadlock detection, thread switching
- **Collect diagnostics** — automated thread dumps and class listings
- **Bulk set breakpoints** from a file for repeatable debugging sessions

## Skill Structure

```
jdb-debugger/
├── SKILL.md                        # Main skill instructions
├── agents/
│   ├── jdb-debugger.agent.md       # Orchestrator — triages and delegates
│   ├── jdb-session.agent.md        # Interactive debugging sub-agent
│   ├── jdb-diagnostics.agent.md    # Quick diagnostics sub-agent
│   └── jdb-analyst.agent.md        # Read-only analysis sub-agent
├── scripts/
│   ├── jdb-launch.sh               # Launch a JVM under JDB
│   ├── jdb-attach.sh               # Attach JDB to a running JVM
│   ├── jdb-diagnostics.sh          # Collect thread dumps & diagnostics
│   └── jdb-breakpoints.sh          # Bulk-load breakpoints from a file
└── references/
    ├── jdb-commands.md              # Complete JDB command reference
    └── jdwp-options.md              # JDWP agent configuration options
```

## Custom Agents

The skill includes a multi-agent chain for orchestrated Java debugging workflows. The agents are defined as `.agent.md` files and can be used with VS Code Copilot's custom agent feature.

### Agent Architecture

```
User → JDB Debugger (orchestrator)
         ├── jdb-session       → Interactive debugging (launch/attach, breakpoints, stepping)
         ├── jdb-diagnostics   → Quick JVM health checks (thread dumps, deadlock detection)
         └── jdb-analyst       → Read-only analysis (stack traces, root cause reports)
```

| Agent | Role | Tools | User-Invocable |
|-------|------|-------|----------------|
| `JDB Debugger` | Orchestrator — triages requests and delegates | `read`, `search`, `agent` | Yes |
| `jdb-session` | Interactive JDB sessions (launch/attach) | `execute`, `read`, `search` | No |
| `jdb-diagnostics` | Automated diagnostics collection | `execute`, `read` | No |
| `jdb-analyst` | Read-only analysis of traces and logs | `read`, `search`, `web` | No |

### Usage

1. Copy the `agents/` directory into your project's `.github/agents/` folder (or keep it alongside the skill)
2. Open VS Code Copilot Chat and select the **JDB Debugger** agent from the agent picker
3. Describe what you need:
   - *"Debug the NullPointerException in WarningApp"* → routes to `jdb-session`
   - *"Collect a thread dump from port 5005"* → routes to `jdb-diagnostics`
   - *"Analyze this stack trace"* → routes to `jdb-analyst`

## Quick Start

### Use with Claude Code

```bash
/skill install jdb-debugger
```

### Use with Claude.ai

Upload the `jdb-debugger/` directory as a custom skill via **Settings > Capabilities**.

### Use via API

Attach the skill directory to your API request per the [Skills API guide](https://docs.claude.com/en/api/skills-guide).

## Prerequisites

- **JDK** installed (any version with `jdb` — JDK 8+)
- **Bash** shell
- For remote debugging: the target JVM must be started with JDWP:
  ```bash
  java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005 -jar myapp.jar
  ```

## Script Usage

All scripts support `--help` for full usage details.

```bash
# Launch a new JVM under JDB
bash scripts/jdb-launch.sh com.example.Main --sourcepath src/main/java

# Attach to a running JVM
bash scripts/jdb-attach.sh --port 5005

# Collect diagnostics
bash scripts/jdb-diagnostics.sh --port 5005 --output /tmp/diagnostics.txt

# Load breakpoints from file
bash scripts/jdb-breakpoints.sh --breakpoints my-breakpoints.txt --port 5005
```

## Blog Posts & Announcements

- [Substack — Enabling AI Agents to Use a Real Debugger Instead of Logging](https://brunocborges.substack.com/p/enabling-ai-agents-to-use-a-real)
- [LinkedIn — Enabling AI Agents to Use a Real Debugger Instead of Logging](https://www.linkedin.com/pulse/enabling-ai-agents-use-real-debugger-instead-logging-bruno-borges-uty4e/)
- [Foojay — Enabling AI Agents to Use a Real Debugger Instead of Logging](https://foojay.io/today/enabling-ai-agents-to-use-a-real-debugger-instead-of-logging/)
- [DEV Community — Enabling AI Agents to Use a Real Debugger Instead of Logging](https://dev.to/brunoborges/enabling-ai-agents-to-use-a-real-debugger-instead-of-logging-bep)
- [Medium — Enabling AI Agents to Use a Real Debugger Instead of Logging](https://medium.com/@brunoborges/enabling-ai-agents-to-use-a-real-debugger-instead-of-logging-7d8250940845)
- [X/Twitter — Announcement](https://x.com/brunoborges/status/2023504791192617148)

## License

Apache-2.0
