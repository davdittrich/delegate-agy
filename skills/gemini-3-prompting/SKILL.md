---
name: gemini-3-prompting
description: How to write effective prompts when delegating to or reviewing with agy (Gemini 3.1/3.5 via the Antigravity CLI). Use when constructing an agy-bridge prompt for --type search/code/analysis/review/implement, when a delegated result comes back off-target, or when writing an adversarial review brief for Gemini. Triggers on: delegate to agy, ask Gemini, agy prompt, second opinion, review with Gemini.
---

# Prompting Gemini 3 through agy

You drive `agy` (Antigravity, Gemini 3.1/3.5) in **print mode** through `agy-bridge`. Print mode is headless: one prompt in, one result out. The agent **cannot stop to ask a clarifying question**, so the prompt you send is the entire brief. Write it like a work order for a fast, literal junior engineer.

The prompt travels via **stdin**; agy reads files itself from its workspace (`--type code/analysis/review/implement` grant read access). So describe *what to do*, point at *where to look*, and let agy read.

## How Gemini 3 behaves — and how to prompt for it

1. **It follows instructions literally.** "Fix the bug" → it fixes *a* bug its own way. "Make `parseDate` return `null` on empty input and add a test" → exactly that. Spell out the target behavior, not the vibe.
2. **It is terse by default.** Gemini 3 gives direct answers and skips narration. If you want a written plan or an explanation, ask for it explicitly.
3. **It plans and decomposes well.** Give it the *goal* and the *constraints*; let it own the *how*. Over-scripting each step fights the model.
4. **Long context, but order matters.** Put the data/code/diff **first**, then your instruction **last**. Anchor the ask to the material ("Based on the diff above, …").
5. **Negative constraints go LAST.** "Do NOT touch the public API", "do NOT reformat unrelated files" — Gemini 3 can drop a negative constraint that appears too early in a long prompt. Put the *don'ts* at the very end. (This is why `--digest` appends its contract last.)
6. **One markup style.** Markdown headings or simple labels are enough. Don't mix XML tags and Markdown in the same prompt.

Model selection is a **flag, not a sentence.** agy exposes `--model`; the bridge auto-selects per `--type` (search→Flash, everything else→Pro). Never write "use Gemini 3.1 Pro" inside the prompt — pass `--model "<exact name>"` instead (`agy models` for names).

## A solid delegate prompt has five parts

1. **Goal** — one sentence, the outcome you want.
2. **Acceptance criteria** — how *you* will know it's done (tests pass, endpoint returns X, build green). Turns a vague request into a checkable one.
3. **Where to look** — the files, dirs, or modules that matter. Saves agy a blind search.
4. **Scope boundaries** — what NOT to touch (other modules, public API shape, unrelated formatting). **Put these last.**
5. **Output expectation** — code change only, or also a short summary of what changed and why. Add `--digest` when you only want the compressed findings.

Keep it tight. A focused 8-line brief beats a 40-line essay; over-stuffed context buries the actual ask.

## Choosing the --type (and what it may touch)

| Use | `--type` | When |
|-----|----------|------|
| Web-grounded lookup with source URLs | `search` | "latest", pricing, release notes, changelogs |
| Read-only reasoning over code | `code` / `analysis` | "explain how X works", root-cause, large-file analysis — no writes |
| Adversarial second opinion on a diff | `review` | independent cross-model critique; read-only, adversarial framing |
| Actually write files | `implement` | agy reads + writes; still no shell exec |

If unsure whether a task should write, start read-only (`code`) to get the plan, then re-run `implement` to apply it. Always **verify agy's output yourself** — a different model has different blind spots, and it can be confidently wrong.

## Examples (on this bridge)

```bash
# Investigation — data-first, question anchored, read-only
echo "Given src/auth/*.ts, explain how token refresh is triggered and where it can race." \
  | agy-bridge --type analysis

# Adversarial review — the diff is the material, the ask is last, negative constraint LAST
git diff main...HEAD | { cat; echo; echo "Review the diff above for correctness and edge cases. \
Be skeptical. Do NOT comment on formatting."; } | agy-bridge --type review

# Delegation with the 5-part brief + digest (compressed reply)
agy-bridge --type code --digest -- "Goal: list every retry site. \
Acceptance: a table of file:line + backoff strategy. Where: src/net/**. \
Output: digest only. Do NOT include unrelated files."
```

## Limits to be honest about

- **Print mode won't ask questions.** Ambiguity becomes a guess — front-load the detail.
- **Empty reply = failure, not silence.** agy exits 0 with empty stdout on quota `RESOURCE_EXHAUSTED (429)`; the bridge/shim now fail loud (exit 3) with the reason. Wait for reset — re-prompting won't help.
- **Auth is the user's job.** OAuth via Google account, no API key.

See also: [`skills/agy-delegate/SKILL.md`](../agy-delegate/SKILL.md) for when to reach for the bridge and its type/model routing.
