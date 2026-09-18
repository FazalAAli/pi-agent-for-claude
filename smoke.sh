#!/usr/bin/env bash
# Smoke-checks the pi agent for claude mod: the manifest scans clean, an Agent call on the
# `pi` type is answered by pi rather than by a Claude subagent, the run is a
# real subagent the engine lists while it is running, and its output streams
# (chunks arrive before the step ends, not all at once).
#
# Needs a build that dispatches agent.spawn and turn.step (2.1.275+; 2.1.263
# does not). Override the binary with CLAUDE=... to test another one.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1
claude_bin=${CLAUDE:-claude}

$claude_bin plugin validate "$here" >/dev/null
echo "validate: ok"

sessions=$(mktemp -d)
listing=/tmp/pi-smoke-listing.txt
timing=/tmp/pi-smoke-timing.txt
trap 'rm -rf "$sessions" "$listing" "$timing"' EXIT
rm -f "$listing" "$timing"
export PI_CODING_AGENT_SESSION_DIR="$sessions"

# A throwaway plugin records what the engine lists the moment a spawn returns,
# which is the only point a running agent is in `$.agent.list()`.
watch="$sessions/watch"
mkdir -p "$watch/.claude-plugin" "$watch/hooks"
printf '{ "name": "watch", "version": "0.0.1", "description": "records the agent listing" }\n' \
  > "$watch/.claude-plugin/plugin.json"
printf '{ "description": "records the agent listing when a spawn returns", "modules": ["./register.ts"] }\n' \
  > "$watch/hooks/hooks.json"
cat > "$watch/hooks/register.ts" <<'TS'
import type { On } from 'claude-code'

/** Writes the engine's agent listing as each spawn returns, so a test can read it. */
export function register(on: On) {
  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    const agents = await $.agent.list()
    await $.process.run(['tee', '/tmp/pi-smoke-listing.txt'], { stdin: JSON.stringify(agents) })
    return started
  })

  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined) return yield* next(e)
    const t0 = await $.clock.now()
    const inner = next(e)
    let log = ''
    let r = await inner.next()
    while (!r.done) {
      if (r.value.kind === 'text' || r.value.kind === 'thinking') log += `${(await $.clock.now()) - t0} chunk\n`
      yield r.value
      r = await inner.next()
    }
    log += `${(await $.clock.now()) - t0} done\n`
    await $.process.run(['sh', '-c', 'cat >> /tmp/pi-smoke-timing.txt'], { stdin: log })
    return r.value
  })
}
TS

out=$($claude_bin --plugin-dir "$watch" --plugin-dir "$here" -p \
  "Use the Agent tool with subagent_type \"pi-agent-for-claude:pi\" and prompt \"Write three short sentences about the sea.\". Report its answer verbatim." \
  </dev/null 2>&1)

fail() { echo "$1" >&2; printf '%s\n' "$out" >&2; exit 1; }

find "$sessions" -name '*pi-*' -print -quit | grep -q . \
  || fail "route: FAILED - no pi session was created, so pi never ran"
echo "route: ok (pi ran its own session for the subagent)"

grep -q '"type":"pi-agent-for-claude:pi"' "$listing" 2>/dev/null \
  || fail "listing: FAILED - not a listed subagent: $(cat "$listing" 2>/dev/null)"
echo "listing: ok - $(cat "$listing")"

chunks=$(grep -c ' chunk$' "$timing" 2>/dev/null || true)
first=$(awk '/ chunk$/ {print $1; exit}' "$timing" 2>/dev/null || true)
done_ms=$(awk '/ done$/ {print $1; exit}' "$timing" 2>/dev/null || true)
[[ "${chunks:-0}" -ge 3 && -n "$first" && -n "$done_ms" && "$first" -lt "$done_ms" ]] \
  || fail "stream: FAILED - $(tr '\n' ' ' < "$timing" 2>/dev/null)"
echo "stream: ok ($chunks chunks, first at ${first}ms, step done at ${done_ms}ms)"
