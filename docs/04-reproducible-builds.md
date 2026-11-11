# Reproducible builds

## What this buys you

An SBOM that only lists sources lets you audit *what went into* a build. An SBOM
whose artifact hashes are reproducible lets you **verify that a shipped binary
matches** it. The second is a much stronger claim, and it is what this setup
provides.

Verified: two runs of the same commit produce byte-identical firmware.

| Artifact | Status | Shipped |
| --- | --- | --- |
| `zephyr.bin` | byte-identical | yes -- this is what gets flashed |
| `zephyr.elf` | byte-identical | yes -- for debugging |
| 41 of 42 `.a` archives | byte-identical | no |
| `zephyr/libzephyr.a` | differs at archive level | no |
| `zephyr.map` | differs | no |

## The two settings that make it work

### 1. `SOURCE_DATE_EPOCH`

`sbom_build.sh` exports it, pinned to the commit timestamp:

```bash
SOURCE_DATE_EPOCH="$(git -C "$PWD" log -1 --format=%ct)"
export SOURCE_DATE_EPOCH
```

binutils and GCC read this instead of the wall clock. It is the standard lever
and costs nothing.

### 2. `build_info.cmake` has to honour it

This is the part that is specific to tl_matter, and the part that is easy to
miss.

`examples/platform/telink/build_info.cmake` used to take the build timestamp
from `datetime.now()` at CMake configure time:

```cmake
execute_process(
    COMMAND python3 -c "from datetime import datetime; print(datetime.now().strftime('%Y-%m-%d %H:%M:%S'))"
    OUTPUT_VARIABLE BUILD_TIMESTAMP
)
```

and bake it into the firmware:

```cmake
target_compile_definitions(app PRIVATE
    BUILD_TIMESTAMP="${BUILD_TIMESTAMP}"
)
```

`AppTaskCommon::PrintFirmwareInfo()` prints it. So every build carried the
moment it was compiled, and two builds of the same commit could never match.

The fix derives the value from `SOURCE_DATE_EPOCH` when it is set, and keeps the
wall-clock fallback otherwise:

```cmake
if (DEFINED ENV{SOURCE_DATE_EPOCH})
    execute_process(
        COMMAND python3 -c "import os, datetime; print(datetime.datetime.fromtimestamp(int(os.environ['SOURCE_DATE_EPOCH']), datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%S'))"
        OUTPUT_VARIABLE BUILD_TIMESTAMP
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
else()
    execute_process(
        COMMAND python3 -c "from datetime import datetime; print(datetime.now().strftime('%Y-%m-%d %H:%M:%S'))"
        OUTPUT_VARIABLE BUILD_TIMESTAMP
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
endif()
```

**The timestamp stays real** for field debugging. It is only made deterministic
when the build asks for it. There is no trade-off here -- unlike blanking the
date outright, which was the first idea and would have cost the firmware useful
information.

## The two remaining differences, and why they are harmless

**`zephyr.map`** records the temporary object names GCC's LTO pass creates under
`/tmp`, for example `ccVnKmiy.ltrans0.ltrans.o`. Those names are random per
build, and about 890 lines of the map differ because of them. They do not reach
the linked output -- `zephyr.elf` is identical -- and the map is a build report,
not something that ships.

**`zephyr/libzephyr.a`** differs while the `zephyr.elf` it feeds does not, which
points at archive-level metadata such as member order under parallel
compilation rather than object contents. It is an intermediate that does not
ship. Worth knowing if a future consumer hashes intermediates rather than the
firmware.

## Verifying reproducibility yourself

Two builds of the same commit cannot run at the same time: the workflow's

```yaml
concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: true
```

cancels overlapping runs on the same ref. So the two builds must be sequential.

```bash
# Build A: push, or dispatch once and wait for it to finish
gh workflow run telink-build-sbom.yaml --ref <branch>
# ... wait ...

# Build B: dispatch again, same commit
gh workflow run telink-build-sbom.yaml --ref <branch>
# ... wait ...

# Compare
gh run download <A> -n telink-firmware -D a
gh run download <B> -n telink-firmware -D b
cmp a/zephyr.bin b/zephyr.bin && echo "reproducible"
```

Two traps:

- **`gh run rerun` replaces the previous attempt's artifacts.** It re-runs the
  same run, so you cannot get both sets from it. Use two separate
  `workflow_dispatch` runs.
- **Dispatching twice in a row cancels the first.** Wait for each to finish.

## If reproducibility regresses

**Diff two builds of the same commit before reasoning about the build system.**

This is not generic advice; it is the specific lesson from finding this bug.
Locating the cause took one comparison of two firmware images:

```
cmp a/zephyr.elf b/zephyr.elf
  -> differ at char 793285, same total size

read the bytes there
  -> A: "2026-11-09 11:52:43"   B: "2026-11-09 12:01:55"
  -> immediately followed by "\t build timestamp: %s"
  -> everything around it (commit hash, branch, remote, component revisions)
     was identical

grep the format string
  -> AppTaskCommon.cpp:553   LOG_DBG("...", BUILD_TIMESTAMP)

grep BUILD_TIMESTAMP
  -> examples/platform/telink/build_info.cmake
```

That gave the file offset, the virtual address, the exact bytes and the source
line. Six earlier rounds of reading CMake and Kconfig in search of a missing
macro did not find it, and two of those rounds produced confident wrong
answers.

Useful commands:

```bash
cmp a/zephyr.elf b/zephyr.elf            # first differing offset
readelf -l zephyr.elf                    # map file offset -> virtual address
strings zephyr.elf | grep -E '[0-9]{2}:[0-9]{2}:[0-9]{2}'   # embedded times
```

`scripts/tools/telink/gn_sources_to_spdx.py` is a working example of parsing an
ELF's program headers in Python if you need to do the offset-to-address mapping
without a toolchain installed.

## A red herring worth knowing about

Matter has its own build-date macros:

```c
/* src/include/platform/CHIPDeviceConfig.h */
#ifndef CHIP_DEVICE_CONFIG_FIRMWARE_BUILD_DATE
#define CHIP_DEVICE_CONFIG_FIRMWARE_BUILD_DATE __DATE__
#endif
```

They look like the obvious culprit and are documented as "useful for
deterministic builds". **They are not the cause here**, and overriding them
does nothing on Telink -- because `CHIPDeviceConfig.h` pulls its project config
in through `CHIP_DEVICE_PROJECT_CONFIG_INCLUDE`, a different macro from the
`CHIP_PROJECT_CONFIG_INCLUDE` that Telink's `args.gni` sets. Telink never sets
the device one, so that include is empty and every `#ifndef`-guarded value in
`CHIPProjectConfig.h` is silently ignored.

That is a real defect worth reporting upstream, but it is a separate one. If you
find yourself editing `CHIPProjectConfig.h` to change build behaviour and
nothing happens, this is why.
