

https://github.com/user-attachments/assets/0bd4f5e4-c2d5-4e49-a882-30bf01357248

# pi agent for claude

Run [pi](https://pi.dev) as a native Claude Code subagent: it shows in the
agent list, streams live, takes follow-ups, and opens in a tmux pane as a
teammate, while the model behind it is anything pi can reach.

```
> Have pi run with model kimi k2 and summarize this repo.

⏺ pi-agent-for-claude:pi(Summarize repo)
  ⎿ ▸ bash: {"command":"ls -la && git log --oneline -10"}
    ▸ bash: {"command":"cat package.json"}
    This repo is an Expo/React Native calling app with a Go admin service...

    — answered by pi, openrouter/moonshotai/kimi-k2
```

> **Experimental:** built on Claude Code's early-access function hooks and
> some undocumented engine behaviour, so Claude Code updates may break it.

## Requirements

- Claude Code 2.1.275+
- [pi](https://pi.dev), logged in to at least one provider
- Node.js
- macOS or Linux
- tmux, for teammate panes

## Setup

Add to `~/.claude/settings.json` (shell variables alone don't reach teammate
panes):

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_FUNCTION_HOOKS": "1",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "tmux"
}
```

Install from a Claude Code session, then restart (inside tmux for teammate
panes):

```
/plugin marketplace add FazalAAli/pi-agent-for-claude
/plugin install pi-agent-for-claude@pi-agent-for-claude
```

To develop it, load a clone from disk instead:
`claude --plugin-dir /path/to/pi-agent-for-claude`.

## Usage

Ask Claude for pi in plain language; it picks the `pi-agent-for-claude:pi`
agent type.

- **Spawn:** "Have pi review the error handling in src/api."
- **Pick a model:** "Have pi run with model kimi k2 and …". Claude adds a
  `pi-model: <pattern>` line, passed to `pi --model`; otherwise pi uses its
  default. `pi --list-models <search>` lists models.
- **Follow up:** messages to a running pi agent continue its pi session and
  model.
- **Teammate pane:** name it. "Spawn a pi agent named piper to …"

Answers end with `— answered by pi, <provider/model>`, read from pi's own
events. Trust it over what the model says about itself.

## Security

pi runs its own read/bash/edit/write tools, outside Claude Code's permission
prompts, tool policy and safety classifier. A pi agent can change files
without asking. Restrict pi in its own config if that matters.

## How it works

Claude Code starts a real subagent; the plugin replaces only its model
requests (`turn.step`) with a detached `pi --mode json` run, streaming pi's
text, thinking and tool calls. Hook calls get 10 s, so long runs span steps
chained through a no-op `pi_progress` tool. pi's final answer goes back as
text, `SubagentHandback`, or `SendMessage` for teammates, with pi's real
token usage.

## Limitations

- **No hooks, no pi.** With function hooks off, a "pi" agent runs as Claude
  Haiku. Claude is told to flag answers missing the `— answered by pi` line,
  but check yourself. For teammates, the variable must be in settings `env`.
- **Relies on undocumented engine behaviour:** the 10 s hook budget,
  subagent transcript files under `~/.claude/projects/`, exact engine message
  text, and `ps` to detect teammates.
- **`pi_progress` calls** appear in the transcript about every 7 s on long
  runs.
- **Cost figures** for pi agents are priced as Claude tokens; check your
  provider's billing.
- **Teammate shutdown** requests go to pi as plain messages; close the pane
  yourself.

## Troubleshooting

- **"pi ended with no answer"** plus a pi error: usually an unresolvable
  model pattern, or a provider pi isn't logged in to.
- **Anything else:** run `claude --debug` and search the log for
  `pi-agent-for-claude` and `hook failed`.

## Testing

`./smoke.sh` runs an end-to-end check against real pi (costs a few cents).
`claude plugin validate .` checks the manifest and hooks module.

## License

MIT. See [LICENSE](LICENSE).
