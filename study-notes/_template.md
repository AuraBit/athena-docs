# Study Note Template

* Tool: <tool or topic name>
* Summary: <one-line summary, shown as-is in the generated index — keep it
  to a single line, no trailing period, this exact string is what
  `gen-study-index.sh` copies into the table>
* Phase introduced: <NN-phase-slug>
* Related ADRs: <one or more paths, comma-separated, each resolvable from
  the estate root, e.g. `athena-infra/docs/adr/0001-k3d-dual-cluster-shape.md`
  or, for an estate-level ADR filed in this repo,
  `athena-docs/docs/adr/0002-aws-native-story-on-zero-budget.md` — at least
  one path is required and `check-study-notes.sh` verifies every path
  resolves to a real file>
* Last reviewed: <YYYY-MM-DD>

This is the canonical skeleton every study note in this directory follows —
copy it, fill every section, and keep the five headings in this exact order.
`scripts/check-study-notes.sh` mechanically enforces the header fields and
all five headings; it does not enforce prose quality, so the discipline
below is on the author, not the checker.

**Completeness rule:** a section with nothing to say yet still gets its
heading, with an explicit marker (`_Not yet filled._`) under it. Silently
omitting a heading makes a gap invisible — one line making the gap explicit
keeps it a visible to-do instead. The checker only requires the heading to
exist; use the marker anyway so a human skimming the file sees the same gap
the checker would eventually catch on a stricter pass.

## Mental model

What this tool actually *is*, in two or three sentences pitched at someone
who has never used it. This is the section that makes the rest of an
interview answer coherent — get this wrong and every other section reads as
disconnected trivia. Write the sentence you would actually say out loud
first, not a dictionary definition copied from the tool's own homepage.

## Common interview questions

Real questions with the answer sketched inline, not just the question list —
a question without an answer here is a to-do, not a study note. Prefer
questions this project's own ADRs and RESEARCH.md already forced a real
answer to over generic textbook questions; the goal is an answer you can
give from this file alone, without opening the code.

## Gotchas hit in this project

Only things that genuinely bit during execution in this estate — symptom,
cause, fix, each traceable to a real deviation, live-verified finding, or
troubleshooting entry in a SUMMARY.md or runbook. Something you know about
the tool in general but never actually hit here belongs under Common
interview questions or nowhere, not here — padding this section with
textbook caveats is exactly the kind of generic advice every other
candidate also has.

## War stories

The industry incident or the concrete failure mode that motivates a control
this estate actually implements, with the connection to what was built here
made explicit — name the real control, the real file, the real ADR. A war
story with no traceable connection to something in this estate is generic
security-blog content, not interview material specific to this project.

## Command cheat-sheet

The handful of commands actually reached for while building or operating
this piece of the estate — not an exhaustive CLI reference. Prefer the exact
invocation used in a script or runbook in this estate over a paraphrase.

```bash
# example — replace with real commands actually used in this estate
```
