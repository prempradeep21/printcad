# V1 — Voice + point editing ("drill a hole in the center of this face")

## Context
Prem wants to point at a face or edge, speak an instruction, press Enter, and see the edit appear almost immediately. Example: on a 2 mm plate, "draw a hole in the center of this surface" should become a sketch circle at the face centre plus a through-cut. The request is to use TypeSafe AI's **Jev** classifier as the decision maker.

The work goes in the real app, `Software projects/printcad`, not in Amoeba, which only holds docs. AI was listed as deferred. Prem approved lifting that deferral: add task **V1** to `docs/printcad/ROADMAP.md`.

### Is Jev the right tool? Yes, for the decision step only
- **Good fit:** Jev picks one option from a list you define (up to 255 per question). It returns a confidence score and takes about 70–500 ms. It can't make up an operation that doesn't exist, and several questions can go in one call at almost no extra time. "Which edit, where, how deep" is exactly that kind of choice.
- **Poor fit:** it can't produce numbers or coordinates ("no generation, not a calculator"). It also can't plan multi-step jobs. So it chooses the recipe, and plain Swift code does the rest: reads the numbers from the transcript and computes the geometry.
- **Alternatives considered:** Claude or another cloud LLM takes 3–8 s, which misses the "almost immediately" goal. Apple's on-device model takes about 1 s and needs OS 26. Both could be added later as a fallback for hard requests, but they're not in V1.
- **Expected speed:** live on-device transcription, then a Jev call (about 0.2–0.5 s, and usually zero wait because it starts while you're still talking), then about 0.1 s to rebuild a simple part. **Under half a second after Enter.**

## Architecture
```
Mic ─► VoiceCaptureService (on-device SFSpeechRecognizer, partial results) ─► live transcript
Click face/edge ─► VoiceContext (snapshot: face plane, centre, normal, size / picked edges)
transcript + context ─► JevClient (one call, parallel Choice questions) ─► VoiceDecision + confidence
transcript ─► SpokenNumberParser (5 mm, 2.5mm, M3, "through") ─► sizes (else defaults)
VoiceRecipe (pure) ─► [AgentExecOp] ─► AgentBridge.executeAsOneStep ─► session.recordAndRebuild (1 undo)
```
- **Jev questions (one request):**
  - `action` ∈ {hole, fillet_edges, chamfer_edges, extrude_face_out, cut_face_in, shell_remove_face, undo_last, not_understood}
  - `placement` ∈ {face_center, clicked_point, not_applicable}
  - `depth` ∈ {through_all, blind, not_applicable}

  The state sent is short: the transcript plus a one-line description of what's selected. Short input avoids the accuracy drop Jev shows when you send extra, irrelevant text.
- **Speculative call:** each time the partial transcript stays unchanged for about 300 ms, call Jev with it. When Enter is pressed and the text hasn't changed since, reuse that answer.
- **Low confidence:** if confidence is below 0.6 (the exact cut-off gets tuned later), show the top 2–3 choices as buttons in the panel rather than guessing.
- **Failures:** if OCCT fails, show the message in the panel and keep the last valid model (rule 9).

## Files (all in `Software projects/printcad/`)
**New, in `openshape3d/Voice/`:**
- `VoiceCaptureService.swift`: AVAudioEngine + `SFSpeechRecognizer`, with `requiresOnDeviceRecognition` and `shouldReportPartialResults`. Contextual strings: fillet, chamfer, extrude, mm.
- `VoicePanel.swift`: bottom-centre modal. Shows the live transcript, a chip naming the selection (e.g. "Face · planar · 40×20 mm"), a mic level meter and the result/error line. Enter commits and Esc closes.
- `VoiceContext.swift`: builds a snapshot from `toolContext` (EditorViewModel.swift:7188; plane, profile, faceTriangles) or from `blendSelectedEdges` (:3552).
  - The face centre is the true area centroid, from `OCCTKernel.faceInfo` (OCCTKernel.swift:642), converted to world coordinates the way `AgentBridge.listFaces` (:885) does it.
  - If that fails, it falls back to `plane.origin`.
- `JevClient.swift`: `URLSession` POST to `https://api.typesafe.ai/v1/systemone` with a 2 s timeout. The API key is stored in the Keychain, following the pattern in `AIControl.swift`. No SDK is added (rule 5).
- `VoiceIntent.swift`: pure code. It defines the question sets and decodes Jev's reply. It also holds `SpokenNumberParser` and `VoiceRecipe`, which turns decision + context + numbers into `[AgentExecOp]`. For a hole that's `sketch.create` on the face plane, `sketch.addEntities` with the circle, then `feature.extrude` with subtract, throughAll, pointing into the body.

**Modified:**
- `Agent/AgentBridge.swift`: add an internal `executeAsOneStep(_ ops:)` so sketch + cut is one Undo step. First check whether `DocumentSession` already supports grouping undo steps.
- `UI/EditorView.swift`: add a mic button right after Fit View (:1596), with an accessibilityIdentifier, a hidden label for the overflow menu, and a shortcut (⌘⇧V).
- Settings: add a "Jev API key" field.
- `project.pbxproj` build settings:
  - `INFOPLIST_KEY_NSMicrophoneUsageDescription`
  - `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`
  - `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT`
  - `ENABLE_OUTGOING_NETWORK_CONNECTIONS`
- Docs: add V1 to `docs/printcad/ROADMAP.md` and update `PROGRESS.md` at the end.

**Defaults:**
- Hole diameter is 5 mm when you don't say a size.
- "M3" means 3 mm plus the profile's 0.2 mm clearance, so 3.2 mm.
- A size you say in mm is used exactly as said.

## Getting access to Jev
There are two ways in. Both are plain HTTPS calls from `URLSession`, so no SDK or new dependency is needed.

| Route | Endpoint | Auth | Status |
|---|---|---|---|
| **TypeSafe direct** (preferred) | `POST https://api.typesafe.ai/v1/systemone` | API key from console.typesafe.ai | Early access. Prem signs up there or emails hello@typesafe.ai |
| **Cloudflare Workers AI** (available now) | `POST https://api.cloudflare.com/client/v4/accounts/<acct>/ai/run`, model `typesafe/jev` | Cloudflare API token | No waitlist listed. Zero data retention, same price ($0.042 per 1M input tokens, output free) |

- **Cost:** there's no free tier. TypeSafe has none, and new early-access sign-ups are paused as of late September 2026. Prem already has a key, so **TypeSafe direct is the default** and Cloudflare is the fallback. Cloudflare's free 10,000 Neurons/day allowance may or may not cover Jev; that's unconfirmed.
  - Each command is about 2k input tokens. Speculative calls while you speak can mean around 5 calls per command, so about 10k tokens, which is about $0.0004.
  - 1,000 voice commands a month comes to roughly **$0.40**.
- `JevClient` is a Swift protocol with three implementations:
  - `TypeSafeJevClient`
  - `CloudflareJevClient`
  - `OfflineStubClient`, a simple keyword matcher. It lets V1.1–V1.3 be built and tested before any key exists, and is also what the tests use.
- Settings has a backend picker and a key field. The key is stored in the Keychain, the same way as the pairing code in `AIControl.swift`. It's never written in the code or committed.
- Prem supplied a TypeSafe key on 2026-09-28; it lives only in the gitignored `.env.local` (see Step 0) and, at runtime, the Keychain.
- The first real call does a latency check: the Enter→rebuilt time is logged. If Cloudflare turns out slower than direct, switch when the early-access key arrives.

### Step 0: save Prem's key (first thing after approval)
Prem has a TypeSafe key (`apikey_…`), so **TypeSafe direct becomes the default backend**. Cloudflare stays as a fallback.

1. Add `.env.local` to `printcad/.gitignore`. Right now it has no env entries. Check `git status` / `git check-ignore` to confirm the file is ignored **before** writing it.
2. Write `printcad/.env.local` containing the line `JEV_API_KEY = <key>`. That format is also valid xcconfig syntax.
3. Add a gitignored `Config/Secrets.xcconfig` that does `#include? "../.env.local"`, and set it as the Debug base config. At build time, the key becomes a Debug-only Info.plist value.
4. On first debug launch, `JevKeyStore` copies that value into the Keychain. From then on the app only reads the Keychain. The Settings field can override it, and Release builds never contain the key.
5. The opt-in live test `JevLiveSmokeTests` reads `JEV_API_KEY` from the environment and is skipped when it's missing, so CI never needs the key.
6. The key is never echoed in commit messages, PROGRESS.md, logs or the plan.

## Priority & phasing (recommended)
CLAUDE.md allows one task ID per session, so V1 is split into small tasks. Each one ships working and ends with a green test run.

| Task | Delivers | Actions |
|---|---|---|
| **V1.1** Voice panel + mic | Mic button next to Fit View, bottom-centre panel, live on-device transcript, selection chip, Enter / Esc. No AI yet: Enter just shows what would be sent. | — |
| **V1.2** Jev client + number parser | `JevClient` (Keychain key, 2 s timeout, speculative call), `SpokenNumberParser`, number-role questions, confidence handling with choice buttons. Tested with a stubbed network. | — |
| **V1.3** Core face & edge recipes | One-undo composite executor + `VoiceContext` with the face centroid. **Covers sample commands 1–7:** hole (centre or clicked point, through or blind), fillet, chamfer, push/pull, boss, shell, plus undo/redo. | A hole, cut-in · B push/pull, boss · C fillet, chamfer · D shell · J undo/redo |
| **V1.4** Conversational tweaks | modify_last ("make it 6", "2 mm deeper"), repeat-last-on-this ("same again here"), rectangular pocket and pad, delete / move face. | I modify_last · N repeat · A pocket · B pad · D delete/move face |
| **V1.5** Body ops + view | Mirror, linear and circular pattern, move/rotate, scale, duplicate, boolean, hide/delete, view commands. **Covers sample commands 8–9.** | E · K |
| **V2** Selection helpers | "all top edges", "every edge of this face", "opposite face", "hover = this" (no click needed), selecting several things. | M · UX |
| **V3** Richer features | Hole patterns, counterbore/countersink (after F21), slots, text, sketch-by-voice, reference planes, variables, measure / print check, Claude fallback for not_understood. | A extras · G · H · I vars · L |

Why this order:
- V1.1–V1.3 get your hole-in-the-centre case working end to end as early as possible.
- V1.4 makes voice feel faster than the mouse, because you can adjust without re-selecting.
- Body ops use recipes that already exist, so they're cheap but not urgent.
- Selection helpers are the biggest remaining UX improvement, but they need new geometry queries, so they come after.

## Action catalog (what Jev can choose between)

### How the questions are asked
Each Enter press sends **one Jev call**. All of the questions below go in it and are answered in parallel.

1. **`action`**: one Choice. The option list is **filtered by what is selected** (face, edge, body, nothing, or inside a sketch), so Jev never sees actions that can't apply. Fewer options means more accurate answers, and it stays well under the 255 limit.
2. **Slot questions**: small Choices for placement, direction, depth, axis and so on. Every one includes a `not_applicable` option.
3. **Number roles**: plain code pulls every number out of the transcript, e.g. "3 mm hole 10 mm deep" gives [3, 10]. Jev is then asked one Choice per number: *what is this number?* ∈ {diameter, radius, depth, distance, thickness, count, angle, spacing, width, height, length}. Jev doesn't write numbers, but it can label them, and that gets around its biggest limitation.
4. **`confidence`**: comes back with every answer. Low confidence shows choice buttons instead of acting.

Status column: ✅ = already exists as an agent op or app command and only needs a voice recipe. 🔨 = needs a new composite or feature.

### A. Holes & cuts (target: face)
| Action | Example phrase | Built from | Status |
|---|---|---|---|
| hole | "drill a 5 mm hole in the centre", "through hole here" | sketch circle + extrude subtract | ✅ recipe |
| hole_pattern | "four holes in the corners, 3 mm from the edges" | circles × n + one cut | 🔨 |
| counterbore / countersink hole | "M3 countersunk hole here" | F21 fastener tool | 🔨 (after F21) |
| slot | "10 mm slot, 3 wide, across the middle" | slot sketch + cut | 🔨 |
| rectangular pocket | "20 by 10 pocket 2 deep" | rectangle + cut | ✅ recipe |
| cut face in | "cut this face in 1 mm" | pushPull negative | ✅ |

### B. Add material (target: face)
| Action | Example | Built from | Status |
|---|---|---|---|
| extrude / push-pull out | "pull this up 5 mm" | pushPull | ✅ |
| boss (cylinder on face) | "add a 10 mm post, 8 tall, in the centre" | circle + extrude union | ✅ recipe |
| rectangular pad | "add a 20 by 20 block on top" | rectangle + extrude union | ✅ recipe |
| offset face | "offset this face 0.5" | offsetFace | ✅ |

### C. Edge finishing (target: edge(s))
| fillet | "round this 2 mm" | fillet | ✅ |
| chamfer | "chamfer 1 mm" | chamfer | ✅ |
| offset edge | "offset edge 1 mm" | model.offsetEdge | ✅ |

### D. Face editing (target: face)
| Action | Example | Status |
|---|---|---|
| move face | "move this face 3 mm out" | ✅ moveFace |
| rotate face / draft | "tilt this 5 degrees", "add 2° draft" | ✅ rotateFace / draftFace |
| scale face | "make this face 20% bigger" | ✅ scaleFace |
| delete face | "remove this face" | ✅ deleteFace |
| shell (open this face) | "hollow it out, 1.2 mm walls, open here" | ✅ shell |
| replace face | "make this face match that one" | ✅ replaceFace (needs 2 picks) |

### E. Body operations (target: body, or the body owning the pick)
| Action | Example | Status |
|---|---|---|
| duplicate | "duplicate this 30 mm to the right" | 🔨 (copy + move composite) |
| move / rotate | "move it up 10", "rotate 90 about Z" | ✅ transform |
| mirror | "mirror across this face", "mirror on X" | ✅ mirror (keepOriginal) |
| linear pattern | "make 4 copies, 15 apart" | ✅ pattern |
| circular pattern | "6 around the centre" | ✅ pattern |
| scale | "scale to 150%", "make it 2 mm wider" | ✅ scaleUniform / NonUniform |
| boolean | "join these", "subtract this from that" | ✅ union / subtract / intersect |
| split | "split at this face" | ✅ model.split |
| delete / hide / show | "delete this", "hide it" | ✅ |

### F. Create from nothing (target: empty space, or a face used as the base)
| add primitive | "add a 20 mm cube", "a 10 mm sphere on top" | ✅ primitive |
| revolve / loft / sweep | "revolve this sketch 360" | ✅ (needs a sketch pick) |

### G. Sketch (target: face → start a sketch, or inside an open sketch)
| sketch on face | "sketch here" | ✅ |
| add shape | "centred circle 8 mm", "rectangle 20 by 10", "hexagon 6 across" | ✅ circle / rect / polygon |
| text | "write PREM on this face, 5 mm tall, cut 0.5" | ✅ sketch.text + cut |
| sketch mirror / offset / trim | "offset this 1 mm" | ✅ |
| finish sketch | "done" | ✅ |

### H. Reference geometry
| offset plane / angled plane / axis | "plane 10 mm above this face" | ✅ plane.offset etc. |

### I. Dimensions & variables
| modify last | "make it 6", "bigger", "2 mm deeper" | 🔨 (edits the last feature's dimension) |
| set variable | "set wall to 2" | ✅ (Variables exist) |
| use variable | "make the hole diameter bolt_d" | 🔨 |

### J. History
| undo / redo | "undo that" | ✅ |
| delete last feature / edit feature | "remove the last fillet", "edit the hole" | ✅ (History re-enter) |

### K. View
| fit / top / front / iso / zoom to selection | "show from top", "zoom in on this" | ✅ view.* |
| hide others / isolate | "just show this" | 🔨 small |

### L. Inspect & print
| measure | "how thick is this", "distance to that face" | 🔨 (reply is spoken text) |
| print check | "will this print", "check overhangs" | 🔨 (F20) |
| export | "export STL" | ✅ project.export |

### M. Selection helpers (make voice work on groups of things)
| expand selection | "all top edges", "every edge of this face", "the opposite face", "all holes" | 🔨 |
Voice is weak at pointing to many items one by one, so this matters a lot: "fillet all the top edges 1 mm" becomes *expand selection* followed by *fillet*.

### N. Meta
| not_understood · cancel · repeat last on this | "same again here" | ✅ / 🔨 |

### Slot questions (Choices, all asked in the same call)
- `placement` ∈ {face_centre, clicked_point, corners, along_edge, not_applicable}
- `depth_mode` ∈ {through_all, blind, up_to_next, not_applicable}
- `direction` ∈ {into_body, out_of_body, both_sides, +X, −X, +Y, −Y, +Z, −Z, not_applicable}
- `axis` ∈ {X, Y, Z, this_edge, face_normal, not_applicable}
- `boolean_intent` ∈ {add, cut, new_body, intersect, not_applicable}
- `relative` ∈ {absolute_value, increase_by, decrease_by, set_to, not_applicable} (handles "2 mm deeper" versus "make it 6")
- number roles (per extracted number, see above)

## Tests (written first, per rules 2–3; each V1.x adds its own)
The list below covers V1.1–V1.3. Later tasks follow the same pattern: a pure test for each recipe, plus one real-geometry test per action.
- V1.4: modify_last on a hole changes its diameter and needs only one undo.
- V1.5: pattern count and spacing come out right, and mirror keeps the original.
- `SpokenNumberParserTests`: "5 mm", "5mm", "2.5 millimetres", "M3", "five millimetres", sentences with no number, and sentences with two numbers (e.g. "3 mm hole 10 mm deep").
- `VoiceRecipeTests` (pure): the hole recipe produces three ops with the correct plane, centre, radius, subtract and throughAll. The fillet recipe passes on the picked edge indices.
- `JevClientTests`: request encoding checked against fixture JSON, reply decoding, low-confidence replies turning into choice buttons, and timeout/HTTP errors turning into panel messages. The network is stubbed with `URLProtocol`.
- `VoiceHoleGeometryTests` (real `EditorViewModel`, same pattern as `CircleCenterInputTests.swift:6`):
  - On a 40×20×2 plate, pick the top face and run the recipe. Volume should drop by π·2.5²·2, and there should be exactly one new undo step. Undo should bring the volume back.
  - On an L-shaped face, the hole centre should be the area centroid.

## Verification
1. Run `xcodebuild test …` on the iPad Pro 13" simulator and confirm the full suite is green, with the count recorded in PROGRESS.md.
2. Run by hand in "Designed for iPad" on the Mac:
   - Sketch a rectangle and extrude it 2 mm.
   - Click the mic, click the top face and say "drill a hole in the center". The words should appear live.
   - Press Enter. The hole should appear in under 1 s.
   - ⌘Z should remove it in one step.
   - Try a low-confidence phrase and check that choice buttons appear.
3. Log the Enter→rebuilt time in debug builds so the latency target can be measured.

## Future UX ideas (V2+, see phasing above)
- **Hover as "this":** whatever face is under the pointer while you speak counts as the target, so you don't need to click.
- **Push-to-talk:** hold a key (e.g. Space) to talk instead of opening a modal.
- **Several targets:** select multiple edges or faces and say "fillet these 1 mm".
- **Follow-up tweaks** to the last edit: "bigger", "make it 6", "move it left 5". This adds a `modify_last` action that edits the dimension of the feature just made.
- **Variables by voice:** "set wall thickness to 2".
- **Fastener words:** "M3 counterbore", once F21 lands.
- **Fallback:** when Jev picks not_understood, hand the request to Claude, which already has the existing Agent op catalog.
