# Teaching AI Agents to Use a Real Debugger Instead of `System.out.println`

Every Java developer has been there. Something breaks, and the first instinct is to litter the code with `System.out.println(">>> HERE 1")`. Then `HERE 2`. Then `HERE 3 — value is: " + x`. Rebuild. Rerun. Stare at the console. Repeat.

We've been doing this for decades. And now, so have our AI agents.

When you ask an AI coding assistant to debug a Java application, it almost always reaches for the same playbook: add logging statements, recompile, rerun, read the output, and reason about what happened. It's the `println` debugging loop, automated — but it's still `println` debugging.

What if the agent could just... use a real debugger?

## The JDK ships a perfectly good debugger. Nobody uses it.

Every JDK installation since the beginning of time includes `jdb` — the Java Debugger. It's a command-line tool that lets you set breakpoints, step through code, inspect variables, catch exceptions, and examine threads. It speaks the same JDWP protocol that IntelliJ and Eclipse use under the hood.

And it's **purely text-based**, which makes it a perfect tool for AI agents that operate through terminal commands.

The problem is that no agent knows how to use it. Until now.

## Agent Skills: Teaching new tricks through Markdown

Anthropic's [Agent Skills](https://agentskills.io/specification) framework lets you package instructions, scripts, and reference material into a structured directory that AI agents can load dynamically. The format is simple: a `SKILL.md` file with YAML frontmatter and Markdown instructions, plus optional helper scripts and reference docs.

Think of a skill as a runbook that the agent reads just-in-time when it recognizes a relevant task. The key insight is **progressive disclosure** — the agent only loads the skill's description at startup (~100 tokens), and pulls in the full instructions only when it decides the skill is needed.

I decided to build one that teaches agents how to operate JDB.

## Building the skill: a conversation with Copilot

The entire skill was built in a [single conversation session](https://gist.github.com/brunoborges/3b2f883c62409b6ceeacd0fb5a8dc811) with GitHub Copilot CLI. The process was surprisingly natural — I described what I wanted, and we iterated through research, design, implementation, and testing together.

The conversation started with a simple prompt:

> *"Java (the JDK) has a Debugger CLI. Let's build a skill so that AI agents can debug applications in real time."*

Copilot researched the Agent Skills specification, studied the Anthropic public skills repository for patterns, read Oracle's JDB documentation, and then produced the complete skill — all within the same session.

### What the skill contains

The resulting [`jdb-debugger-skill`](https://github.com/brunoborges/jdb-debugger-skill) has a clean structure:

```
jdb-debugger-skill/
├── SKILL.md                        # Core instructions for the agent
├── scripts/
│   ├── jdb-launch.sh               # Launch a JVM under JDB
│   ├── jdb-attach.sh               # Attach to a running JVM
│   ├── jdb-diagnostics.sh          # Automated thread dumps
│   └── jdb-breakpoints.sh          # Bulk-load breakpoints from a file
└── references/
    ├── jdb-commands.md              # Complete command reference
    └── jdwp-options.md              # JDWP agent configuration
```

The `SKILL.md` opens with a **decision tree** — a pattern borrowed from Anthropic's own webapp-testing skill — that guides the agent to the right approach:

```
User wants to debug Java app →
  ├─ App is already running with JDWP agent?
  │   ├─ Yes → Attach: scripts/jdb-attach.sh --port <port>
  │   └─ No  → Can you restart with JDWP?
  │       ├─ Yes → Launch with: scripts/jdb-launch.sh <mainclass>
  │       └─ No  → Suggest adding JDWP agent to JVM flags
  │
  ├─ What does the user need?
  │   ├─ Set breakpoints & step through code → Interactive JDB session
  │   ├─ Collect thread dumps / diagnostics → scripts/jdb-diagnostics.sh
  │   └─ Catch a specific exception → Use `catch` command in JDB
```

Then it provides concrete debugging workflow patterns — how to investigate a `NullPointerException`, how to watch a method's behavior, how to diagnose a deadlock — written as step-by-step JDB command sequences the agent can follow.

## The real test: debugging a buggy Swing app, live

To prove this wasn't just theoretical, we built a sample Swing application with four intentional bugs:

1. **NullPointerException** — `processMessage()` returns `null` for empty input
2. **Off-by-one error** — the warning counter always shows one less than actual
3. **NullPointerException after clear** — `warningHistory` is set to `null` instead of `.clear()`
4. **StringIndexOutOfBoundsException** — `text.substring(0, 3)` on input shorter than 3 characters

Then we debugged it. In the same conversation session. With the agent driving JDB.

### The debugging session

The agent launched the app under JDB, set exception catches and method breakpoints, and ran the application:

```
> catch java.lang.NullPointerException
> catch java.lang.StringIndexOutOfBoundsException
> stop in com.example.WarningApp.showWarning
> run
```

When I clicked "Show Warning" in the Swing UI, JDB immediately hit the breakpoint. The agent stepped through the code, inspecting variables at each step:

```
Breakpoint hit: "thread=AWT-EventQueue-0", com.example.WarningApp.showWarning(), line=80
80            String text = inputField.getText();

AWT-EventQueue-0[1] next
Step completed: line=83
83            String processed = processMessage(text);

AWT-EventQueue-0[1] print text
 text = "bruno"
```

It stepped into `processMessage`, verified the return value, then stepped back out:

```
AWT-EventQueue-0[1] step
Step completed: com.example.WarningApp.processMessage(), line=105
105            String trimmed = message.trim();

AWT-EventQueue-0[1] step up
Step completed: com.example.WarningApp.showWarning(), line=83

AWT-EventQueue-0[1] print processed
 processed = "⚠ BRUNO ⚠"
```

Then came the moment where it caught the off-by-one bug red-handed. The agent stepped to the counter update and inspected the state:

```
AWT-EventQueue-0[1] print warningCount
 warningCount = 0

AWT-EventQueue-0[1] next
Step completed: line=93
93            counterLabel.setText("Warnings shown: " + (warningCount - 1));

AWT-EventQueue-0[1] print warningCount
 warningCount = 1
```

There it is. `warningCount` is `1`, but line 93 displays `warningCount - 1`, which is `0`. The agent identified the bug by observing the live state of the program at the exact line where the defect occurs — no logging, no guessing, no recompilation.

### A small but important lesson: compile with `-g`

One interesting moment in the session: the first time we tried `locals`, JDB responded:

```
Local variable information not available. Compile with -g to generate variable information
```

The agent immediately recognized the issue, quit JDB, recompiled with `javac -g` (which includes debug symbols), and relaunched. This is exactly the kind of practical knowledge that a skill should encode — and that we later made sure to document in the SKILL.md.

## Why this matters

### Beyond `println` debugging

The standard AI debugging loop today looks like this:

1. Read the code
2. Add `System.out.println` or logging statements
3. Recompile
4. Run the program
5. Read the output
6. Reason about what happened
7. Modify the code
8. Repeat

With JDB, the agent can:

1. Set breakpoints at suspicious locations
2. Run the program
3. Inspect the **actual runtime state** — variable values, call stacks, thread states
4. Step through execution line by line
5. Catch exceptions at the exact throw site

This is a fundamentally different approach. The agent observes the program's behavior **as it runs**, rather than inferring it from log output after the fact.

### Interactive debugging as a first-class agent capability

What makes this work so well is the combination of:

- **JDB being text-based** — it reads commands from stdin and writes output to stdout, which is exactly how AI agents interact with tools
- **Agent Skills being just Markdown** — no SDK, no API integration, no plugin framework. You write instructions in a `.md` file and the agent follows them
- **Helper scripts as black boxes** — the agent runs `scripts/jdb-attach.sh --port 5005` without needing to understand the script internals

The skill follows the same "black-box scripts" pattern used by Anthropic's own [webapp-testing skill](https://github.com/anthropics/skills/tree/main/skills/webapp-testing), which uses Playwright scripts the agent invokes without reading their source.

### The shift from static analysis to dynamic observation

Most AI coding tools today work with **static** information — source code, type signatures, documentation. JDB gives agents access to **dynamic** information — what actually happens at runtime. This is especially valuable for:

- **Concurrency bugs** — thread dumps and deadlock detection through JDB's `threads` and `where all` commands
- **State-dependent bugs** — inspecting object fields and local variables at specific points in execution
- **Exception investigation** — catching exceptions at the throw site rather than reading stack traces after the fact
- **Integration issues** — attaching to running services to observe behavior with real data

## Try it yourself

The skill is open source: **[github.com/brunoborges/jdb-debugger-skill](https://github.com/brunoborges/jdb-debugger-skill)**

The repository includes a sample Swing app with the four intentional bugs described above, so you can reproduce the exact debugging session. The full conversation transcript is available as [a GitHub Gist](https://gist.github.com/brunoborges/3b2f883c62409b6ceeacd0fb5a8dc811).

To get started:

```bash
# Clone and compile the sample app with debug symbols
cd sample-app
javac -g -d out src/main/java/com/example/WarningApp.java

# Launch under JDB
jdb -sourcepath src/main/java -classpath out com.example.WarningApp
```

Or, if you're using Claude Code:

```
/skill install jdb-debugger
```

Then just ask: *"Debug my Java application — there's a NullPointerException I can't figure out."*

## What's next

This is a starting point. The skill currently covers the core JDB workflow, but there are natural extensions:

- **Conditional breakpoints** and watchpoints for more surgical debugging
- **Integration with build tools** — auto-detecting Maven/Gradle projects and compiling with `-g` before launching JDB
- **Remote debugging recipes** — patterns for Kubernetes pods, Docker containers, and cloud-hosted JVMs
- **Composability with other skills** — combining JDB debugging with code analysis or test-generation skills

The bigger takeaway is this: every command-line tool that developers use daily is a potential agent skill. Debuggers, profilers, database CLIs, network tools — they're all text-based interfaces waiting to be taught to AI agents.

The JDK gave us the debugger thirty years ago. We just needed to write the instructions.
