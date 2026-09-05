# ComfyUI: multi-chunk video with latent continuation and per-chunk prompts

Research notes, September 2026. Goal: a ComfyUI setup that generates a long video as a
sequence of chunks, where each chunk is conditioned on the **last N frames of the previous
chunk in latent space**, each chunk has **its own prompt and its own length**, and the whole
thing runs **in one queue** from a single prompt list.

## Recommendation

Use **Wan 2.2 I2V-A14B + Stable Video Infinity (SVI) 2.0 Pro LoRAs**, driven by the
`WanImageToVideoSVIPro` node (ComfyUI-KJNodes, native ComfyUI sampler path), wrapped in a
loop that reads a prompt list and a length list. The ready-made workflow closest to the spec
is yorgash's **"WAN2.2 SVI v2.0 Pro Simplicity - infinite prompt, separate prompt lengths"**
on Civitai (model 2279224).

Why this and not the alternatives:

- It is the only mainstream approach where continuation is *pure latent*. The node takes the
  last `motion_latent_count` latent slots of the previous clip's latent and concatenates
  them (after the anchor image latent) into the I2V conditioning. No decode/encode between
  clips, so no VAE round-trip drift at seams. Verified in the node source (see below).
- Per-clip prompt is natural: every clip is its own I2V conditioning.
- Per-clip length is just the `length` input (frames, 4n+1).
- Evidence is the strongest of any option: SVI is an ICLR 2026 oral paper, the repo has
  ~2.6k stars, the SVI maintainers keep a curated list of community ComfyUI workflows with
  "Verified"/"Recommended" markers, and Kijai (KJNodes author) published a native example.

## How the SVI Pro node actually works (verified from source)

`WanImageToVideoSVIPro` in `ComfyUI-KJNodes/nodes/nodes.py`:

```python
inputs: positive, negative, length (default 81, step 4),
        anchor_samples (LATENT), prev_samples (LATENT, optional),
        motion_latent_count (default 1, 0..128)

total_latents = (length - 1) // 4 + 1
if prev_samples is None or motion_latent_count == 0:
    image_cond_latent = anchor_latent
else:
    motion_latent = prev_samples["samples"][:, :, -motion_latent_count:]
    image_cond_latent = cat([anchor_latent, motion_latent], dim=2)
image_cond_latent = cat([image_cond_latent, zero_padding], dim=2)
mask = ones(...); mask[:, :, :1] = 0      # only the anchor slot is hard-locked
positive/negative += {"concat_latent_image": image_cond_latent, "concat_mask": mask}
```

Consequences:

- One latent slot is 4 pixel frames (Wan VAE stride), so `motion_latent_count=1` carries the
  last 4 frames, `2` carries 8, and so on. Kijai's native example uses `0` for the first clip
  and `1` for every extension clip.
- The **anchor** is the original reference image for every clip (identity anchor), not the
  last frame. That is what stops long-run identity drift.
- The first output slot of each clip repeats the anchor, so workflows trim the seam with
  `ImageBatchExtendWithOverlap` (KJNodes) or `WanCutLastSlot` (Well-Made nodes).
- `length` is per-clip, so mixed clip lengths are supported by the node itself. Community
  guidance: keep each clip at 81 frames (121-frame clips were reported to degrade colour).
  "Longer" scenes are therefore best expressed as several 81-frame clips with the same
  prompt, which a prompt-list loop handles trivially.

Kijai's native example (`wan22_SVI_Pro_native_example_KJ.json`, linked from the SVI repo
issue #51) uses only: `DiffusionModelLoaderKJ`, `LoraLoaderModelOnly` (Lightx2v + SVI Pro
HIGH/LOW rank-128 fp16), `CLIPTextEncode`, `WanImageToVideoSVIPro`, `SamplerCustomAdvanced`
with `SplitSigmas` for the high/low experts, `ImageBatchExtendWithOverlap`, `VHS_VideoCombine`.
Three stages chained via `latent -> prev_samples`.

## Option A: yorgash "Simplicity" workflow (closest to the spec)

Source: Civitai model 2279224 (v3.1 hotfix). Civitai and its mirrors are blocked from this
environment, so the description below is assembled from search-engine snippets of the page.

- Input: prompts, **one per line**; clip lengths as a **comma-separated list**; one Settings
  node; hit run. Author: "you basically have to use the settings node only, just set size and
  prompt, then run."
- Per-loop LoRA selection via "Use at part: 2, 4".
- v3.0 reduced dependencies to ComfyUI-KJNodes, ComfyUI-Easy-Use (for the loop), rgthree;
  v3.1 replaced Lora-Manager with rgthree Power LoRA and fixed a subgraph/image bug.
- Ships a "fully extended (no subgraph)" variant for debugging.
- Can extend an existing video ("Use source video").
- Comments visible in snippets are positive ("This workflow is great").
- Not verified: download/like counts, and whether the length list maps 1:1 to prompt lines
  or per-loop 81-frame multiples. Check the page.

Fit to the three requirements: simple (one text box + one length list), per-chunk length,
one-go. Continuation is SVI Pro latent continuation.

## Option B: Well-Made/ComfyUI-Wan-SVI2Pro-FLF (explicit groups, keyframe control)

https://github.com/Well-Made/ComfyUI-Wan-SVI2Pro-FLF (84 stars, updated March 2026).

- `WanImageToVideoSVIProFLF`: same as the KJNodes node plus optional `end_samples` to pull
  a clip toward a target last frame, and `WanCutLastSlot` to drop the hard-locked end slot
  before it is fed to the next clip.
- Three workflows (I2V with KSampler Advanced, I2V with SamplerCustomAdvanced, video
  extension), 7 clip groups by default; duplicate a group to add clips.
- Per-clip prompt and per-clip `length`, single queue run. Not a prompt-list loop: each clip
  is a visible group. Issue #1 asks exactly for "continue with prompt only, automatically";
  no maintainer answer as of this research.

Good if you want optional keyframes at chunk boundaries; heavier to edit than Option A.

## Option C: FramePack with timestamped prompts (closest syntax, weakest model)

https://github.com/ShmuelRonen/ComfyUI-FramePackWrapper_Plus (114 stars).

- `FramePackTimestampedTextEncode`: one text box with `[0s: prompt]` or `[2s-5s: prompt]`
  blocks; gaps are filled with the previous prompt; timestamps snap to section boundaries;
  `prompt_blend_sections` for soft transitions. Global `total_second_length`.
- FramePack itself is "latent context" by design: every ~1 s section is conditioned on a
  compressed stack of previous latents. F1 sampler for forward generation.
- Downsides: HunyuanVideo-based model from spring 2025, image-to-video only, visibly lower
  quality and motion than Wan 2.2. Multiple users (e.g. Wan2GP issue #1065) judge SVI to be
  better for long videos than FramePack. The timestamp feature started as an unmerged PR in
  Kijai's wrapper and lives on in forks.

## Option D: LTX-2.3 / LTX-2.5 looping sampler and native multi-shot

- `LTXVLoopingSampler` + `MultiPromptProvider` (Lightricks/ComfyUI-LTXVideo,
  `looping_sampler.md`): temporal tiles of `temporal_tile_size` with `temporal_overlap`
  latent frames conditioned from the previous tile; prompts given as `"p1|p2|p3"`, one per
  tile; last prompt repeats. One-go, latent overlap, but **all tiles are the same size**.
- LTX-2.5 (August 2026, open weights, 16 GB VRAM minimum) adds native multi-shot: write the
  whole sequence in prose ("A hard cut to a close-up ...") and a duration head sets clip
  length; total 2-20 s per generation. Not chunked continuation, and no per-shot seconds.
- Kijai published an "Extend Any Video" LTX-2.3 workflow using ReTake masks; multi-extend
  variants exist but are manual, 10-20 s per extension.

## Option E: Kijai WanVideoWrapper context windows + "|" prompts

Single pass over a long frame count with sliding context windows (e.g. 1025 frames, window
81, overlap 16). Multiple prompts separated by `|` are "spread evenly across the windows;
there is no more accurate method". One-go and latent, but no per-chunk length and
prompt/segment alignment is approximate.

## Option F: LongCat-Video (native continuation)

Meituan LongCat-Video (7.8k stars, MIT) has a native video-continuation task; the Kijai
wrapper example reuses the last 13 frames per segment, community videos reach 3-4 minutes
with per-segment prompts. Chaining in ComfyUI is manual (one group per segment) and the
model is heavier and less tuned than Wan 2.2 in the community.

## Rejected: pixel-space last-frame loops

`veryrandomstuff/comfyui-wan-loop`, `gregtee2/ComfyUI_VideoChunkTools`, and
`Granddyser/wan-video-extender` all take a decoded last frame (or decoded overlap frames via
VACE) as the next start image. That is a VAE round-trip per chunk and fails the
"in latent space" requirement, although `wan-video-extender` is otherwise close on ergonomics
(per-loop prompt and LoRA, overlap frames, single run).

## Evidence summary

| Item | Source |
|---|---|
| SVI paper, ICLR 2026 oral, 10-14 minute demo videos | github.com/vita-epfl/Stable-Video-Infinity, arXiv 2510.09212 |
| Maintainer-curated workflow list with Verified/Recommended tags, incl. a for-loop variant | SVI repo issue #51 |
| "1-minute videos with no noticeable color degradation when configured properly" | SVI repo issue #51 tips |
| Node mechanics (latent concat, no decode) | ComfyUI-KJNodes nodes.py, `WanImageToVideoSVIPro` |
| Kijai native example: 3 chained stages, motion_latent_count 0 then 1 | wan22_SVI_Pro_native_example_KJ.json |
| Prompt-per-line + comma lengths + loop | Civitai 2279224 (snippets only, page blocked here) |

Recommended settings from the SVI maintainers' thread: 81 frames per clip, 480p-class
resolution (480x832), fp16 LoRAs, minimal LightX2V weight, more sampling steps, different
seed per clip, prompt each clip as "state + motion" continuing from the previous clip's end.

## If the Simplicity workflow's input format is not quite right

The loop is the only part that needs custom nodes. A minimal own build:

1. `ComfyUI-Easy-Use` `forLoopStart`/`forLoopEnd` with `total` = number of chunks.
2. A text node holding the script; split on `======` (KJNodes string nodes or a tiny custom
   Python node), and put the chunk length in a header line, e.g. `[81] a woman walks ...`.
   A JSONL parser is about 30 lines of Python as a custom node.
3. Inside the loop: `CLIPTextEncode` on the chunk prompt, `WanImageToVideoSVIPro` with
   `length` from the header, `prev_samples` from the loop-carried latent, `anchor_samples`
   from the reference image, sampler, carry the latent forward, accumulate decoded frames.
