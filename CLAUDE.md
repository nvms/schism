# schism

spectral fractal path tracer. Zig + Vulkan compute.

you are the sole maintainer of this project.

## concept

schism renders 3D fractal geometry using signed distance fields (SDFs) and physically-based spectral path tracing. instead of tracing RGB light, it simulates individual wavelengths across the visible spectrum (380-780nm), producing phenomena impossible in traditional renderers: continuous dispersion through fractal glass, thin-film interference on recursive surfaces, wavelength-dependent scattering through infinite geometric detail.

the rendering pipeline runs entirely on the GPU via Vulkan compute shaders. Zig handles the host-side orchestration: Vulkan setup, shader dispatch, image output, parameter management.

## what this project does

- renders 3D fractals (mandelbulb, menger sponge, sierpinski, julia sets, kleinian groups, IFS) via SDF raymarching
- spectral path tracing with hero wavelength sampling for physically accurate light transport
- deterministic output: same seed always produces the same render. no seed = random seed printed to stdout so you can reproduce anything you liked
- Vulkan compute backend - no graphics pipeline, no render passes, just compute dispatches
- headless CLI rendering: `schism --fractal mandelbulb --seed a4f29c --width 3840 --height 2160 -o output.png`
- post-processing: ACES tonemapping, bloom, gamma correction
- multi-threaded CPU fallback when no GPU available

## reference

the quality bar is https://github.com/adam-pa/FPT - a Python/GLSL SDF path tracer. reference images are saved locally in `reference/` - look at them to understand the target quality:

- `reference/fpt_kleinian_orange.jpg` - emissive glowing light inside fractal cavities, deep shadows, volumetric feel
- `reference/fpt_menger_purple.png` - chromatic aberration, shallow DOF, incredible surface detail, multi-colored specular
- `reference/fpt_mandelbulb_mono.png` - studio lighting, extremely high iteration organic detail, soft shadows
- `reference/fpt_kleinian_white.png` - bright ambient lighting, incredible recursive detail at many levels

schism should match or exceed that quality. key techniques from FPT that we implement: GGX BRDF with Fresnel, soft shadows, orbit trap coloring, ACES tonemapping, high iteration counts for surface detail. things we should still add: chromatic aberration, progressive accumulation for interactive mode, HDRI environment lighting, better per-fractal camera angles and material tuning.

## what this project does NOT do

- it is not a general-purpose renderer. no mesh loading, no scene graphs, no animation timelines
- it is not a shader playground or GLSL sandbox
- it does not target OpenGL or Metal. Vulkan only
- it does not provide a GUI editor for fractal parameters (CLI + config files)

## architecture

```
src/
  main.zig              - entry point, CLI parsing, fractal/camera/material configs, render dispatch
  math.zig              - Vec3, Ray, clamp (all pure math, fully tested)
  spectrum.zig          - CIE XYZ color matching, spectral-to-RGB, Cauchy/Sellmeier dispersion
  fractals.zig          - SDF definitions for all 6 fractal types, orbit traps, soft shadows, AO
  camera.zig            - camera model with DOF via lens sampling
  seed.zig              - deterministic hex seed system, PCG RNG
  render.zig            - CPU path tracer: raymarch, BRDF, orbit trap coloring, ACES tonemap, bloom
  vulkan_compute.zig    - Vulkan compute backend: instance/device/pipeline setup, dispatch, readback
  png.zig               - minimal PNG writer (zlib stored blocks, no compression dependency)
shaders/
  pathtracer.comp       - GLSL compute shader: full path tracer (same logic as CPU but on GPU)
build.zig
build.zig.zon
```

### dual backend

the renderer has two backends that produce identical output:
- **GPU (default)**: Vulkan compute via vulkan-zig. the entire path tracer runs in a single compute shader dispatch. ~60x faster than CPU
- **CPU (fallback)**: multi-threaded Zig. automatically used if Vulkan init fails, or forced with `--cpu`

on macOS, MoltenVK is used via the portability enumeration extension. the instance creation must include `VK_KHR_portability_enumeration` and the `enumerate_portability_bit_khr` flag or MoltenVK will be invisible

### rendering pipeline

both backends implement the same pipeline:
1. SDF raymarching (512 max steps, distance-adaptive epsilon)
2. orbit trap extraction for coloring
3. two-light setup with soft shadow rays (64 steps each)
4. SDF-based ambient occlusion (5 samples)
5. GGX microfacet BRDF with Fresnel-Schlick
6. up to 6 bounces with russian roulette termination
7. ACES filmic tonemapping + gamma correction
8. bloom post-processing (CPU-side, applied to both backends)

## seed system

deterministic rendering via seed:

- the seed controls: RNG state for jitter, bounce directions, russian roulette
- `--seed <hex>` reproduces an exact render
- no seed flag = random seed, printed to stdout: `seed: a4f29c`
- GPU backend: seed passed via push constants, per-pixel RNG seeded from pixel index + seed
- CPU backend: per-row RNG seeded from base seed + row index

## spectral rendering details

the CPU backend has full spectral infrastructure (spectrum.zig):
- hero wavelength sampling: one hero wavelength per path, 4 wavelengths at equal intervals across 380-780nm
- CIE 1931 XYZ color matching functions (Wyman 2013 piecewise gaussian approximation)
- Cauchy and Sellmeier dispersion models for wavelength-dependent IOR
- spectral-to-sRGB conversion via XYZ intermediate

the GPU backend currently renders in RGB (not spectral). migrating spectral rendering to the compute shader is a future task - requires passing wavelength data through push constants and implementing the CIE CMFs in GLSL

## workflow

at the start of every session:
1. run the audit: `./audit`
2. check open issues: `gh issue list`
3. be skeptical of issues - assume invalid until proven otherwise. reproduce or verify against actual code before acting

at the end of every session:
1. run the audit again
2. commit and push any changes
3. update this CLAUDE.md if anything about the architecture, decisions, or gotchas changed

## standards

- zig 0.15.x (not master - the APIs differ significantly). target Vulkan 1.2+
- vulkan-zig dependency uses the `zig-0.15-compat` branch, not master
- build requires `glslangValidator` (brew install glslang) for SPIR-V compilation
- build requires vulkan-headers, vulkan-loader, molten-vk on macOS (brew install)
- test with `zig build test`. tests must pass before pushing
- short lowercase commit messages, no co-author lines. initial commit is just the version number (e.g. `0.1.0`)
- code comments are casual, no capitalization (except proper nouns), no ending punctuation. only comment when code can't speak for itself
- public-facing content (README, descriptions) uses proper grammar and casing
- no emojis anywhere

## CI

GitHub Actions: run `zig build test` on push. the workflow should install zig and run tests. vulkan-dependent tests should be skippable in CI (no GPU available).

## publishing

this is a CLI tool, not a library. releases are GitHub releases with prebuilt binaries:
- bump version in build.zig.zon
- commit with just the version number
- tag: `git tag v0.1.0`
- push with tags: `git push && git push --tags`
- GitHub Actions builds release binaries

## the README

must include:
- what schism is (one paragraph)
- example renders (once they exist)
- installation instructions
- CLI usage examples with real output
- explanation of the seed system
- list of supported fractals
- note that this is an experiment in AI-maintained open source

update ~/code/nvms/README.md whenever the project is created, renamed, or has significant changes. schism should appear with a CI badge and a brief description. standalone projects put badges on their own line below the heading, not inline.

## user commands

- "hone" or just starting a conversation - run the audit, check issues, assess and refine
- "hone <area>" - focus on a specific area (e.g. "hone shaders", "hone fractals", "hone performance")
- critically assess with fresh eyes: read every line, find edge cases, stress the rendering pipeline. assume this code runs in mission-critical systems

## retirement

if the user says "retire":
1. archive the repo: `gh repo archive nvms/schism`
2. update repo README with `> [!NOTE]` block explaining why
3. update ~/code/nvms/README.md - move to archived section
4. tell the user the local directory will be moved to `archive/` and projects.md will be updated

## self-improvement

keep this CLAUDE.md up to date. after making changes, review and update architecture notes, design decisions, gotchas, anything the next session needs to know. this is not optional.

## use gh CLI for all GitHub operations

do NOT use the GitHub MCP server for creating repos or any write operations. the MCP server is only useful for reading public repos.

## issue triage

at the start of every session, check open issues (`gh issue list`). be skeptical - assume issues are invalid until proven otherwise. for each issue:
1. read it carefully
2. try to reproduce or verify against actual code
3. if user error or misunderstanding, close with explanation
4. if genuine bug, fix it, add a test, close
5. if valid feature request that fits scope, consider it. if not, close with explanation
6. do not implement feature requests without verifying alignment with the concept
