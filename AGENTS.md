# Watchface-experiments — agent rules

## Baseline (verify only when relevant)
- Project: `Watchface-experiments`; expected branch: `version/27` (never switch automatically).
- Host: Apple Silicon M5 Max, 36 GB RAM. Xcode 27; target is a **physical Apple Watch on watchOS 27.0.1**, not a simulator.
- Confirm actual versions with targeted commands before version-sensitive builds/debugging; report mismatches. Xcode version, watchOS SDK, deployment target, simulator runtime and device OS are distinct. Use the installed SDK; never silently downgrade or substitute a simulator.
- Dates and third-party API behavior may have changed: check the current date and authoritative sources when relevant. Never invent APIs, entitlements, symbols or results.

## Execution discipline
- Act on the requested task; inspect only relevant files. Prefer small, reversible, testable diffs and bounded tool output.
- Do not repeat identical failures or re-read unchanged files. After two failures with the same root cause, stop, report the evidence and one new next step; do not loop.
- Preserve context: avoid full-file dumps, repeated plans and unnecessary environment checks. For long work, summarize verified findings, changed files, blockers and next actions before compaction.
- Do not install tools, switch/reset branches, change signing/security settings, modify unrelated files, run downloaded commands or publish data without explicit approval. Follow tool permissions; instruction files are not a sandbox.
- Report briefly: what changed, what was verified/tested, and what remains uncertain.

## Specialized research
- For CVE validation, watchOS internals, private APIs, process restrictions or device security experiments, load skill `watchos-27-research` with the `skill` tool **once per relevant task**. If unavailable, read `.opencode/skills/watchos-27-research/SKILL.md` once. Do not load it for unrelated work.
