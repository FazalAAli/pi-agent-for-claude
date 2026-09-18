# pi agent for claude

Run [pi](https://pi.dev) as a native Claude Code subagent.

Ask Claude to "have pi look into this" and it spawns a real Claude Code
subagent: it shows in the agent list, streams live, takes follow-up messages,
and opens in its own tmux pane as an agent-team teammate. The model behind
it, though, is whatever pi runs: DeepSeek, Kimi, GPT, anything pi can reach.

```
> Have pi run with model kimi k2 and summarize this repo.

⏺ pi-agent-for-claude:pi(Summarize repo)
  ⎿ ▸ bash: {"command":"ls -la && git log --oneline -10"}
    ▸ bash: {"command":"cat package.json"}
    This repo is an Expo/React Native calling app with a Go admin service...

    — answered by pi, openrouter/moonshotai/kimi-k2
```

> **Experimental.** This is built on Claude Code's function hooks, an
> early-access API that changes between releases without notice, and it
> leans on several undocumented engine behaviours (listed below). Expect a
> Claude Code upgrade to break it now and then.

## Requirements

- **Claude Code 2.1.275 or later.** Earlier builds don't dispatch the
  `agent.spawn` and `turn.step` events this plugin is built on.
- **Function hooks enabled:** `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`.
- **[pi](https://pi.dev)** on your `PATH`, logged in to at least one provider.
- **Node.js** on your `PATH` (it filters pi's event stream).
- macOS or Linux (`sh`, `ps`, `pkill`, `tail`, `nohup`). Windows is not
  supported.
- For teammates in split panes: tmux, and
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## Setup

Put the flags in your Claude Code settings (`~/.claude/settings.json`) so
every Claude process sees them, teammates included:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_FUNCTION_HOOKS": "1",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "tmux"
}
```

Setting the variables only in your shell is not enough for teammates: the
panes tmux opens for them don't inherit the lead's environment.

Then install the plugin. This repo is its own plugin marketplace, so from a
Claude Code session:

```
/plugin marketplace add FazalAAli/pi-agent-for-claude
/plugin install pi-agent-for-claude@pi-agent-for-claude
```

Restart Claude Code (from inside tmux, if you want teammate panes) and it
loads with every session.

To hack on it instead, clone the repo and load it straight from disk; edits
take effect without reinstalling:

```bash
claude --plugin-dir /path/to/pi-agent-for-claude
```

## Usage

Talk to Claude normally; it picks the `pi-agent-for-claude:pi` agent type
when you ask for pi.

- **Spawn a pi subagent:** "Have pi review the error handling in src/api."
- **Choose pi's model:** "Have pi run with model kimi k2 and …". Claude
  starts the prompt with a line `pi-model: <pattern>`, which the plugin
  removes and passes to `pi --model`. Any pattern pi accepts works;
  `pi --list-models <search>` lists them, and the `provider/id` form
  (`openrouter/moonshotai/kimi-k2`) avoids ambiguity. Without it, pi uses its
  own default model.
- **Follow up:** messages sent to a running pi agent continue the same pi
  session, with the same model, until a new `pi-model:` line changes it.
- **Teammate in a split pane:** give the agent a name. "Spawn a pi agent
  named piper to …". pi streams in the pane, and its answer goes back to the
  lead.

Every answer ends with a line naming the model that actually ran, read from
pi's own events. Trust that line over anything the model says about itself:
many models claim to be Claude when asked.

## Security

**pi runs its own tools.** It reads, edits and writes files and runs shell
commands through its own read/bash/edit/write tools, and none of those calls
pass through Claude Code's permission prompts, tool policy or safety
classifier. A pi agent can change your files without anyone being asked.

Restrict what pi may do in pi's own configuration if that matters for your
work, and read what you delegate with that in mind.

## How it works

The spawn itself is untouched, so Claude Code starts a real subagent loop
with its own id, transcript and entry in the agent list. The plugin replaces
only the model request inside that loop:

1. `agent.spawn` records which subagents are pi agents.
2. `turn.step`, the model request of each step, starts
   `pi -p --mode json --session-id pi-<agent id>` detached, piped through a
   small Node filter into a file, and streams what pi writes there as the
   step's text, thinking and `▸ tool` notes.
3. Claude Code gives a hook call 10 seconds. A pi run that takes longer
   spans several steps: each streams for up to 7 seconds, then ends on a call
   to the plugin's no-op `pi_progress` tool, which makes the engine start the
   next step, which carries on reading the same pi run.
4. When pi finishes, its final message is the agent's answer. It goes back
   as plain text, through `SubagentHandback` where the session requires it,
   or through `SendMessage` to the agent that messaged a teammate.

Each step reports pi's token usage under pi's model name, so the agent's
totals are pi's real counts.

## Limitations

- **Fallback without hooks.** If function hooks are off, the plugin's code
  never loads and a "pi" agent runs as Claude Haiku (the `model:` in
  `agents/pi.md`). The agent's description tells the calling Claude that an
  answer without the `— answered by pi, …` line did not come from pi, so it
  says so instead of passing it off as pi's work. That guard is instructions,
  not code; check for the line yourself when it matters.
- **Undocumented engine behaviour.** The plugin depends on things Claude Code
  doesn't promise:
  - the 10-second hook budget
  - follow-ups read from the subagent's transcript file under
    `~/.claude/projects/` (the API returns the main loop's messages instead)
  - engine messages matched by their exact text (`[handback-send-enforce]`,
    `<teammate-message …>`, and others)
  - teammate detection by reading the parent process's command line with
    `ps`
- **Transcript noise.** Long runs show a `pi_progress` call roughly every 7
  seconds. The main Claude also sees that tool; calling it is refused.
- **Costs.** Claude Code may price pi's tokens as if they were Claude
  tokens, so cost figures for pi agents are wrong. Check your provider's
  billing.
- **Teammate shutdown.** Shutdown requests from the lead reach pi as ordinary
  messages, so a pi teammate may not shut down cleanly. Close its pane.
- **Stopping.** Stopping an agent kills its pi process, except in the brief
  moment between two steps, when pi finishes on its own.

## Testing

`./smoke.sh` runs an end-to-end check against real pi and Claude Code (it
costs a few cents): the manifest validates, pi actually runs, the agent is
listed while running, and output streams. Set `CLAUDE=...` to test another
Claude Code binary.

`claude plugin validate .` checks the manifest and what the hooks module
hooks and calls.

## Troubleshooting

- **Claude says pi didn't answer**, or an answer has no `— answered by pi`
  line: function hooks are off in that process. For teammates, check that the
  variable is in your settings `env`, not just your shell.
- **"pi ended with no answer"** followed by a pi error: usually a model
  pattern pi couldn't resolve, or a provider pi isn't logged in to.
- **Anything else:** run `claude --debug` and search the log for
  `pi-agent-for-claude` and `hook failed`.

## License

MIT. See [LICENSE](LICENSE).
