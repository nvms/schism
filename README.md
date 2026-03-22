# schism

Spectral fractal path tracer. Renders 3D fractal geometry using signed distance fields and physically-based spectral path tracing, producing phenomena impossible in traditional RGB renderers: continuous light dispersion through recursive geometry, thin-film interference on fractal surfaces, wavelength-dependent scattering through infinite detail.

Built with Zig and Vulkan compute shaders.

## How it works

Instead of tracing red, green, and blue channels independently, schism simulates light at individual wavelengths across the visible spectrum (380-780nm). When light passes through fractal geometry with wavelength-dependent refraction, it splits into continuous rainbows - not the crude 3-band artifacts RGB renderers produce. Combined with SDF raymarching through mathematically infinite fractal detail and physically-based path tracing for realistic light transport, the results are unlike anything conventional renderers can produce.

## Usage

```
# render a mandelbulb at 4K with a specific seed
schism render --fractal mandelbulb --seed a4f29c --width 3840 --height 2160 -o render.exr

# random seed (printed to stdout so you can reproduce it)
schism render --fractal menger -o render.png
# seed: 7b3e1d

# interactive exploration mode
schism explore --fractal julia
```

## Seed system

Every render is deterministic. Pass `--seed <hex>` to reproduce an exact image. Without a seed, a random one is generated and printed to stdout. The seed is also embedded in EXR metadata, so every render is traceable back to its parameters.

Same seed + same parameters = identical output, every time.

## Supported fractals

- **Mandelbulb** - the 3D analog of the Mandelbrot set
- **Menger sponge** - recursive cubic fractal with infinite surface area and zero volume
- **Sierpinski** - tetrahedral recursive subdivision
- **Julia sets** - 3D quaternion Julia sets
- **Kleinian groups** - limit sets of Mobius transformations
- **IFS** - iterated function system fractals

## Building

Requires Zig (master or latest stable) and Vulkan SDK.

```
zig build
zig build test
```

## About

This project is an experiment in AI-maintained open source - autonomously built, tested, and refined by AI with human oversight. Regular audits, thorough test coverage, continuous refinement. The emphasis is on high quality, rigorously tested, production-grade code.
