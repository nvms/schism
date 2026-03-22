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
- headless CLI rendering: `schism render --fractal mandelbulb --seed a4f29c --width 3840 --height 2160 -o output.exr`
- windowed interactive mode for exploring and framing shots
- post-processing: tonemapping (ACES, etc.), chromatic aberration, bloom, gamma correction

## what this project does NOT do

- it is not a general-purpose renderer. no mesh loading, no scene graphs, no animation timelines
- it is not a shader playground or GLSL sandbox
- it does not target OpenGL or Metal. Vulkan only
- it does not provide a GUI editor for fractal parameters (CLI + config files)

## architecture

```
src/
  main.zig          - entry point, CLI parsing, mode dispatch
  vulkan/           - Vulkan initialization, device selection, pipeline setup
    instance.zig
    device.zig
    pipeline.zig
    buffer.zig
  render/           - rendering orchestration
    engine.zig      - compute dispatch, accumulation, progressive refinement
    camera.zig      - camera model, DOF, lens simulation
    spectrum.zig    - wavelength sampling, spectral-to-RGB conversion (CIE XYZ)
  fractals/         - SDF definitions
    mandelbulb.zig
    menger.zig
    sierpinski.zig
    julia.zig
    kleinian.zig
    ifs.zig
  output/           - image output (PNG, EXR)
    png.zig
    exr.zig
shaders/
  pathtracer.comp   - main compute shader: raymarching + spectral path tracing + BRDF
  postprocess.comp  - tonemapping, bloom, chromatic aberration
  accumulate.comp   - progressive sample accumulation
build.zig
build.zig.zon
```

## seed system

deterministic rendering via seed:

- the seed controls: fractal parameter variations, camera jitter sequences, wavelength hero sampling, random bounce directions
- `--seed <hex>` reproduces an exact render
- no seed flag = random seed, printed to stdout: `seed: a4f29c`
- the seed is embedded in EXR metadata so renders are always traceable

## spectral rendering details

- hero wavelength sampling (Wilkie et al., EGSR 2014): one hero wavelength per path, additional wavelengths at equal intervals across the visible range
- spectral material model: index of refraction varies by wavelength (Cauchy/Sellmeier dispersion), enabling physically accurate prism effects through fractal geometry
- CIE 1931 XYZ color matching functions for spectral-to-display conversion
- spectral power distributions for light sources (not just color temperature)

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

- zig master or latest stable. target Vulkan 1.2+
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
