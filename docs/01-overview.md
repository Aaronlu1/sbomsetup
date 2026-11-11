# How the pieces fit

## The shape of the problem

tl_matter is a fork of connectedhomeip (the Matter SDK) with a Telink platform
port. It does not build on its own -- it needs a Zephyr installation, and that
Zephyr is itself a Telink fork with about twenty modules.

```
tl_matter          Matter protocol stack + example applications
    |
    | TELINK_ZEPHYR_BASE
    v
tl_zephyr          Zephyr RTOS fork, based on Zephyr 4.1.0
    |              west manifest pulls ~20 modules:
    |                hal_telink, mbedtls, openthread, mcuboot, lvgl, ...
    |
    +-- tl_ble_sdk_zephyr    Telink BLE stack (not in the manifest;
                             fetched separately by fetch_sdk.sh)
```

Two environment variables do similar-sounding but different jobs:

| Variable | Set by | Meaning |
| --- | --- | --- |
| `TELINK_ZEPHYR_BASE` | the Telink container | where *their* Zephyr lives |
| `ZEPHYR_BASE` | Zephyr itself | where Zephyr thinks it lives |

The container sets only the first, so every build has to translate. The Matter
Telink builder does this in `scripts/build/builders/telink.py`, and
`sbom_build.sh` copies the same three lines.

## Why a container does most of the work

Building this from scratch means installing the Zephyr SDK, cloning tl_zephyr,
running `west update` for twenty modules, and fetching `hal_telink` blobs --
which need credentials.

`ghcr.io/project-chip/chip-build-telink` already contains all of it: Zephyr SDK
0.17.0 with `riscv64-zephyr-elf`, a pre-cloned tl_zephyr, every west module and
the blobs. It exports `TELINK_ZEPHYR_BASE` and `TELINK_ZEPHYR_SDK_DIR`.

So the pipeline's `container:` line is what makes the whole thing practical.
Without it, none of the rest matters.

The image is pinned by digest, not by tag, so the toolchain cannot shift under
a build. See [`02-setup.md`](02-setup.md) for how to bump it.

## Two build systems, glued together

This is the part that makes SBOM generation awkward, and worth understanding
before reading any of the scripts.

```
Matter side:  GN + Ninja        builds the CHIP library
Zephyr side:  CMake + Kconfig   builds the RTOS, drivers, and links everything
Glue:         config/common/cmake/chip_gn.cmake
              adds GN as a CMake ExternalProject
```

The observed build sequence:

```
west build -b tl3238x
  |
  +-- CMake configure (~9s)
  |     find toolchain, process devicetree, run Kconfig,
  |     run the ZAP code generator, emit ninja rules
  |
  +-- Ninja build (740 steps)
        [1..116]    system prep
        [117]       ZAP codegen
        [118..732]  compile the app, including the GN-built CHIP library
        [733..739]  link libapp.a, then zephyr.elf
        [740]       process_binaries.py (Telink post-processing)
```

## What zspdx can and cannot see

`west spdx` (Zephyr's zspdx) walks the **CMake file-based API codemodel**. It
knows what CMake compiled and nothing else.

That means:

| Build system | Visible to zspdx | Consequence |
| --- | --- | --- |
| Zephyr, modules, HAL | yes | tracked properly |
| The application | yes | tracked properly |
| **The Matter stack (GN)** | **no** | one opaque package, `FilesAnalyzed: false` |

Measured on a real build: **8 Matter-side files tracked against 3883 in `src/`**.
A customer asking "which Matter clusters are in this firmware" got nothing.

`gn_sources_to_spdx.py` closes that gap and is the single most involved piece
here. [`04-reproducible-builds.md`](04-reproducible-builds.md) covers the
related reproducibility work; the GN recovery method is summarised below.

## The GN source recovery, in one page

The obvious approaches do not work. All three were tried:

| Approach | Why it fails |
| --- | --- |
| Read `compile_commands.json` | lists what GN **could** build, not what ninja built. 711 of its 999 entries are never built -- test targets that `chip_build_tests = false` keeps out |
| `gn desc` on the root target | the label `//config/telink/chip-gn:telink` does not resolve, and gn needs the pigweed environment active |
| Filter by compiler | 974 of 999 entries use `riscv64-zephyr-elf-g++`, `pw_unit_test` files included, so it discriminates nothing |

What works is **`.ninja_log`** -- ninja's own record of the commands it
actually executed. Intersecting its outputs with the compile database's `-o`
paths yields exactly the sources that went into the build.

```
<ninja out>/.ninja_log          the outputs ninja produced
        +
compile_commands.json           output .o  ->  source file
        |
        v
288 sources, zero test files
```

The result spread is what the Matter stack should look like: `src/app` 93,
`src/lib` 50, `src/platform` 32, `src/protocols` 28, `src/credentials` 18,
`src/transport` 13, and the rest.

Two details that cost time:

- GN emits **both** the `-o` value and the `file` field relative to the entry's
  own `directory` field, as `../../../../src/lib/support/Base64.cpp`. Resolving
  them against anything else fails silently.
- Matter sources carry **no `SPDX-License-Identifier` tags**. They embed the
  full Apache-2.0 boilerplate, the same way openthread embeds BSD-3-Clause. The
  extractor needs a second pass matching the Apache-2.0 grant sentence.

## The five SPDX documents

zspdx splits its output by source of information rather than by component:

| Document | Packages | Files | Covers |
| --- | ---: | ---: | --- |
| `zephyr.spdx` | 21 | 561 | Zephyr and its modules |
| `matter-sources.spdx` | 1 | 288 | the Matter stack (added by this kit) |
| `build.spdx` | 100 | 76 | CMake build targets |
| `modules-deps.spdx` | 20 | 0 | module dependency references |
| `app.spdx` | 1 | 2 | the example application |

`build.spdx` references the other documents through `ExternalDocumentRef`, with
SHA1 checksums, so the set is provably one product. Note that not every SBOM
consumer follows those references -- check before assuming.

## What each script is for

```
sbom_build.sh          west spdx --init -> west build -> west spdx
                       plus SOURCE_DATE_EPOCH
        |
        +-- app.spdx, build.spdx, modules-deps.spdx, zephyr.spdx
        |
gn_sources_to_spdx.py  .ninja_log + compile_commands.json
        |
        +-- matter-sources.spdx
        |
enrich_sbom.py         fills PackageSupplier, PackageLicenseDeclared, purl
        |              reads module_licenses.json for the fallbacks
        +-- enriched/
        |
        +-- spdx_to_cyclonedx.py   -> telink-matter.cdx.json
        |
        +-- sbom_review.py         -> sbom-review.csv, sbom-gaps.md
```

Order matters. `gn_sources_to_spdx.py` must run before enrichment, so the new
document is enriched too.

## Next

- [`02-setup.md`](02-setup.md) -- stand it up
- [`03-review-workflow.md`](03-review-workflow.md) -- resolve the licenses
- [`04-reproducible-builds.md`](04-reproducible-builds.md) -- verify a binary
- [`05-troubleshooting.md`](05-troubleshooting.md) -- when it breaks
