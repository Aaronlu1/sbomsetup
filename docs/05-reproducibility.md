# 05 · Reproducible builds

## 1. Why it matters

An SBOM is only useful for verifying a shipped binary if the binary can be
reproduced from the same commit. If two builds of the same commit differ, the
SBOM can only audit sources, not prove what was shipped.

## 2. Where non-determinism comes from

Two builds of the same commit differed in:

```
libapp.a
libzephyr.a
libopenthread-ftd.a
zephyr.elf
zephyr_pre0.elf
```

Causes:

- `ar` embeds member mtimes
- the linker writes a build-id
- `BUILD_TIMESTAMP` is compiled into the firmware from `datetime.now()`

The 561 source files themselves hashed identically, so the sources were not the
problem.

## 3. Fix

### 3.1 SOURCE_DATE_EPOCH

`sbom_build.sh` takes the **commit timestamp**:

```bash
SOURCE_DATE_EPOCH="$(git -C "$PWD" log -1 --format=%ct)"
export SOURCE_DATE_EPOCH
```

binutils and GCC read it instead of the wall clock.

### 3.2 build_info.cmake

`files/examples/platform/telink/build_info.cmake` changes `BUILD_TIMESTAMP` to:

```cmake
if (DEFINED ENV{SOURCE_DATE_EPOCH})
    # convert SOURCE_DATE_EPOCH to a UTC timestamp
else()
    # fall back to datetime.now()
endif()
```

Applied, `git diff` should be exactly +22/−5.

### 3.3 What is deliberately not done

No `-ffile-prefix-map`: CI always builds at a fixed path, so paths already
agree. Reproducing on a different machine is a separate question. Measure
before adding more.

## 4. How to verify

Use the **same build directory name** for two clean builds:

```bash
rm -rf out/repro-a
sbom_build.sh <board> <app> out/repro-a out/sbom-a
rm -rf out/repro-a
sbom_build.sh <board> <app> out/repro-a out/sbom-a2
sha256sum out/repro-a/zephyr/zephyr.bin out/repro-a/zephyr/zephyr.elf
```

Both hashes should match.

### Different directory names

If the two builds use different directory names (`repro-a` / `repro-b`), the
ELF differs because DWARF records the build directory. Check with:

```bash
riscv64-zephyr-elf-objcopy --strip-debug repro-a/zephyr/zephyr.elf /tmp/a.elf
riscv64-zephyr-elf-objcopy --strip-debug repro-b/zephyr/zephyr.elf /tmp/b.elf
sha256sum /tmp/a.elf /tmp/b.elf   # should match
```

`zephyr.bin` is unaffected and stays identical.

## 5. The timestamp inside the firmware

```bash
grep -a -o "20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]" zephyr.bin | sort -u
```

It should equal the commit time in UTC, not the build time.
