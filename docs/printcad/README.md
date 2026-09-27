# PrintCAD — Claude Code Doc Pack

PrintCAD is a personal, parametric CAD app for 3D printing on an Ender 3 V3 SE.
It is a hard fork of [OpenShape3D](https://github.com/laanlabs/openshape3d) (MIT; SwiftUI + Metal + OpenCASCADE),
extended with parametric history, variables, a fastener tool and Mac support.

These files are written for Claude Code to execute. Copy this folder into the fork at `docs/printcad/`.

## File map

| File | Who reads it | Purpose |
| --- | --- | --- |
| `README.md` | You | Tonight's runbook (this file) |
| `SETUP.md` | You | Mac, Xcode, fork, signing, first build |
| `CLAUDE-printcad.md` | Claude Code | Rules and context; append to the repo's `CLAUDE.md` |
| `SPEC.md` | Claude Code | What the app must do; decisions; printer profile |
| `ARCHITECTURE.md` | Claude Code | Current fork layout, target design, Swift type sketches |
| `ROADMAP.md` | Both | Milestones M0–M4, task IDs, acceptance criteria |
| `TESTING.md` | Claude Code | Kernel test fixtures U1–U5 with expected numbers |
| `PROMPTS.md` | You | Copy-paste prompts, one per task |
| `PROGRESS.md` | Both | Log Claude Code updates after every task |

## Tonight's session (~2–3 hours)

| Step | Time | What | Done when |
| --- | --- | --- | --- |
| 1 | 30–45 min | Follow `SETUP.md` steps 1–8 | Fork runs in the iPad simulator |
| 2 | 5 min | Copy this folder to `docs/printcad/`; append `CLAUDE-printcad.md` to `CLAUDE.md`; commit | `git log` shows the docs commit |
| 3 | 20 min | Prompt **P0** (orientation) in Claude Code | Claude summarises the repo and confirms the plan |
| 4 | 30 min | Prompt **T0.1** (baseline) | Tests pass; baseline logged in `PROGRESS.md` |
| 5 | 30 min | Prompt **T0.2** (run on Mac as "Designed for iPad") | App runs on your MacBook |
| 6 | stretch | Prompt **T0.3** (Ender build-volume box) | Ghost 220×220×250 box in viewport |

Stop after step 5 if you're tired. Stopping at a green test run is a good night.

## Ground rules for every session

1. One task ID per Claude Code session. Start each with the session opener in `PROMPTS.md`.
2. Claude plans first; you approve; then it codes.
3. Tests must pass before every commit. No green, no merge.
4. Claude updates `PROGRESS.md` at the end of each task.
5. Print something real at the end of every milestone.
