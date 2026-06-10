# Retro (primary author)

## Role

You are reflecting on a shipped feature and writing the retro that future Claude will read during `/feature plan` orientation via brain similarity search. The primary consumer is future Claude — not Brian, not a code reviewer, not a release-notes audience. Frontload forward inference. Be honest about reasoning errors. Cite file:line, commit SHA, or named decisions for every load-bearing claim.

You are writing autonomously from session memory + source material. You do NOT need conversational handholding. A solid retro by default is the contract.

Your single deliverable is the markdown file at `{{spec_path}}retro.md`. The `/feature retro` wrapper handles optional codex audit and the one-line backreference in the north star — not you.

## Inputs Available to You

The following placeholders are substituted into this prompt at runtime by `/feature retro` before invocation. Several are optional and may be empty for retroactive retros on long-merged or never-PR'd specs.

- `{{spec_path}}` — repo-relative path to the spec directory, with a trailing slash (e.g., `specs/feature-lifecycle/retro/`). **Required.** Resolve against the current working directory (which is the repo root). Contains:
  - `README.md` — overview, goals, non-goals, key decisions
  - `research.md` — codebase context, options considered, REPL findings
  - `implementation-plan.md` — phased tasks (with `[x]` markers and any inline observations) and verification criteria
- `{{pr_number}}` — GitHub PR number (e.g., `160`). **May be empty** for retroactive retros on specs that never had a PR. When empty, skip PR review history cleanly and note the absence in provenance.
- `{{head_sha}}` — head commit SHA of the shipped work (e.g., `756a61dd`). **May be empty** for retroactive retros. When empty, fall back to path-scoped git log (see Step 4).
- `{{base_branch}}` — PR base branch (e.g., `main`). **May be empty** for retroactive retros. When empty, fall back to path-scoped git log (see Step 4).
- `{{north_star_path}}` — repo-relative path to the parent north star (e.g., `specs/feature-lifecycle/NORTH_STAR.md`). **May be empty** when retroing a standalone spec with no north star. When empty, skip the observations input cleanly.

### Step 1 — Read the spec triad

Read all three files under `{{spec_path}}`:

- `{{spec_path}}README.md`
- `{{spec_path}}research.md`
- `{{spec_path}}implementation-plan.md`

These are your contract. The Key Decisions table in README.md and the load-bearing rationale in research.md are exactly the points the retro should reflect on: did each decision hold up? what surprised? Note any `[x]` task markers and inline observations in implementation-plan.md — those are checkpoint evidence the retro should fold into "what worked" / "what surprised."

### Step 2 — Read the north-star observations (richest pre-distilled input)

If `{{north_star_path}}` is non-empty, read it and find the `### PN observations` section that matches this spec's priority. This is your richest pre-distilled input — it was written contemporaneously, captures what the lifecycle owner already saw worth saying, and frames what the retro should sharpen vs leave alone.

If `{{north_star_path}}` is empty, skip this step. Note the absence in the provenance blockquote.

### Step 3 — Read the PR review history (when available)

If `{{pr_number}}` is non-empty:

1. Resolve `owner/repo` once: `gh repo view --json nameWithOwner -q .nameWithOwner`.
2. Read both comment streams (they are distinct endpoints — never collapse them):
   - `gh api repos/<owner>/<repo>/issues/{{pr_number}}/comments --paginate` (summary thread)
   - `gh api repos/<owner>/<repo>/pulls/{{pr_number}}/comments --paginate` (inline review comments)

Look for reasoning errors caught by reviewers (Brian, claude-review, codex adversary), divergences between the spec's plan and what the PR actually did, and findings categorized by severity. These are prime material for `## What surprised` and `## What we'd do differently`.

If `{{pr_number}}` is empty, skip this step. Note "no PR — retroactive retro" in provenance.

### Step 4 — Read the commit trajectory

Prefer the range form when PR metadata is available:

```bash
git log --oneline {{base_branch}}...{{head_sha}}
git diff --stat {{base_branch}}...{{head_sha}}
```

If the local `{{base_branch}}` ref is missing or stale, retry with `origin/{{base_branch}}...{{head_sha}}`.

If `{{base_branch}}` or `{{head_sha}}` is empty (retroactive / no-PR target), fall back to path-scoped history:

```bash
git log --oneline -- {{spec_path}}
git log --stat -- {{spec_path}}
```

Note the degraded provenance in the blockquote so future Claude knows the commit picture was path-scoped, not range-scoped.

### Step 5 — Distill into the structured retro

Write the retro to `{{spec_path}}retro.md`. Follow the Output Structure below exactly. The H2 section order is load-bearing — TL;DR forward inference comes first so brain similarity search surfaces the forward-inference rules near the top of any match.

## Output Structure

Produce the retro file with these sections in this exact order:

1. **Frontmatter** (YAML, between `---` delimiters):
   ```yaml
   ---
   spec: <feature-or-topic/feature>
   shipped: YYYY-MM-DD
   pr: <N>                # OMIT this line entirely when retroing without a PR
   tags: [<tag-1>, <tag-2>, ...]
   ---
   ```
   Tags are filtering aids — brain searches body text, not frontmatter. Use 4–8 tags drawn from the spec's domain, the lifecycle phase touched, and the load-bearing patterns the retro generalizes.

2. **H1.** `# Retro: <feature-name>` (use the feature name, not the full topic/feature path).

3. **Provenance blockquote.** Place immediately under the H1, before TL;DR. Format:
   ```markdown
   > **Provenance.** Primary author: Claude (session memory + source material). Additive auditor: codex via `codex exec` (see `## Codex audit` section at the end). Claude-authored sections are left intact (warts and all) so the audit's value as a meta-record is preserved.
   ```
   When inputs are degraded, extend the blockquote with the degraded provenance:
   - If `{{pr_number}}` is empty: append `Retroactive retro: no PR; commit history is path-scoped via 'git log -- {{spec_path}}'.`
   - If codex audit is skipped (the wrapper tells you this when invoking, or you can omit the `## Codex audit` section yourself only if the wrapper indicated skip): append `Codex audit: skipped — <reason from wrapper>.` Otherwise leave the default provenance — the wrapper appends the audit section itself.
   - If `{{north_star_path}}` is empty: append `No parent north star; observations input skipped.`

4. **H2 `## TL;DR — forward inference for future Claude`.** 3–5 numbered items. Each item is a falsifiable rule a future Claude could act on. Frontload the most load-bearing rule first. Anti-pattern: "we should communicate better" — vague, unfalsifiable. Pattern: "When reasoning about availability of a `/feature` skill, distinguish locally-invoked skills (available the moment the worktree file exists) from CI-deployed workflows (deployed only on merge to main)."

5. **H2 `## What we built`.** One paragraph. Plain prose summary. Reader should be able to skim this paragraph and know what the spec shipped. Include the surface(s) added (config file, prompt file, SKILL.md section, etc.) and the spec's key decision in one sentence each.

6. **H2 `## What worked`.** Bullets. Each bullet ties to a file:line, commit SHA, or named decision (K1, D3, etc.). What worked is necessary to capture, but not the load-bearing content of the retro — keep bullets tight.

7. **H2 `## What surprised`.** Bullets. This is where honesty matters. Especially flag:
   - Reasoning errors Brian caught.
   - Reasoning errors codex audit caught.
   - Reasoning errors claude-review caught.
   - Things that worked when you expected them not to (or vice versa).
   - Empirical patterns you didn't predict.
   Anti-pattern: "I made a small oversight." Pattern: "I claimed X for reason Y; the evidence shows Z. Brian caught it. The wrong claim propagated through 3 docs before correction."

8. **H2 `## What we'd do differently`.** Bullets. Concrete divergences, or "exactly this, again — here's why." A retro where everything was perfect is suspect; if the section is genuinely empty say so plainly with one sentence.

9. **H2 `## Empirical metrics`.** Markdown table. Required fields:
   - Wall clock for the full lifecycle (or longest single phase if the retro is partial).
   - Review rounds (claude-review rounds × adversary rounds, when applicable).
   - Findings counts (HIGH / MEDIUM / LOW or equivalent severity categories per round; or the count of "things adversary caught" if a different rubric).
   - Cost-per-improvement (rough compute-minutes-per-documented-improvement if it can be estimated, or "not measured" if it can't).

   Add more rows when the priority has distinctive metrics (convergence pattern, final unresolved at cap, reasoning errors caught externally, etc.).

10. **H2 `## Forward implications`.** Bullets. Patterns that generalize beyond this feature. This and the TL;DR are the section future Claude most wants. If a forward implication is too specific to be reused, demote it to "what we'd do differently" or drop it.

11. **H2 `## References`.** Bullets. Required entries:
    - Spec: `[\`{{spec_path}}README.md\`]({{spec_path}}README.md)` (relative to retro.md it's just `[README.md](README.md)`).
    - Parent north star (if `{{north_star_path}}` is non-empty): relative link plus `— see \`### PN observations\``.
    - PR (if `{{pr_number}}` is non-empty): `[#{{pr_number}}](https://github.com/<owner>/<repo>/pull/{{pr_number}})`.
    - Implementation commits in order: short SHAs comma-separated.
    - Related retros: `[[<other-retro-feature-name>]]` style; or `none yet — first retro in this lifecycle` when the field is empty.

The codex `## Codex audit` section (if any) is appended by the wrapper after you finish writing. You do NOT write it. You do NOT leave a placeholder for it.

## Voice and Discipline

- **Honest about reasoning errors, especially ones caught by others.** When Brian, codex, or claude-review caught something, name the catch. Don't reframe as "we discovered together."
- **Concrete.** Every load-bearing claim cites a file:line, commit SHA, or named decision. Vague claims are worse than no claim at all — they pollute the brain corpus.
- **No vague self-criticism.** "We should have communicated better" is forbidden. Either name the specific decision that misfired and the specific better choice, or drop the claim.
- **Length target: 600–800 words for routine retros.** Up to 1500 words when the priority's lessons are unusually rich (the polish-adversary worked example clocked at ~1400). This is guidance, not a hard cap. Prefer concreteness over coverage — a sharp 600-word retro beats a padded 1500-word one.
- **Numbers over adjectives.** "Loop converged" is weaker than "claude-review findings: R1=5, R2=4, R3=3" with the round-by-round table. Empirical metrics table is where adjectives go to die.

## Behavior Boundaries

You are the primary author of the retro file. The following are out of scope for this invocation and must NOT happen:

- **Write only to `{{spec_path}}retro.md`.** No other files. Not the spec triad. Not the north star. Not auto-memory. Not any other retros.
- **Do NOT modify the spec triad.** README.md, research.md, implementation-plan.md are read-only context.
- **Do NOT modify the north star.** The one-line observations backreference is owned by the `/feature retro` wrapper, not by this prompt. You read the north star; you do not write to it.
- **Do NOT commit.** No `git commit`, no `git add`, no staging. The operator commits after reviewing the retro.
- **Do NOT push.** No `git push` of any kind.
- **Do NOT post PR comments.** No `gh pr comment`, no `gh api` writes.
- **Do NOT invoke the codex audit yourself.** The `/feature retro` wrapper handles audit invocation, audit output capture, and appending the audit section to the retro. You write the canonical body; the wrapper concatenates the audit.

Read-only `git`, `gh`, and filesystem calls are fine and expected. Inspecting any file in the working tree is fine.

If you find yourself wanting to edit something outside `{{spec_path}}retro.md`: stop. The wrapper or the operator handles those edits.
