# Troubleshooting

Every entry here cost at least one CI run to find. They are ordered roughly by
how likely you are to hit them.

## The workflow does not run at all

**Nothing happens when you push.** Check the workflow's path filter:

```yaml
push:
    paths:
        - .github/workflows/telink-build-sbom.yaml
        - scripts/tools/telink/...
        - examples/platform/telink/**
```

A commit touching only, say, `docs/` will not trigger a build. That is
intentional -- documentation does not need a rebuild -- but it surprises people
the first time. Use `workflow_dispatch` to run on demand.

**A push lands but no run appears.** If the fork has never run Actions, GitHub
requires you to enable workflows once. Open the Actions tab and confirm.

## The build fails

### `west spdx` cannot find `zephyr_meta.yml`

```
ERROR: cannot find a valid zephyr_meta.yml required for SPDX generation
```

The build needs `CONFIG_BUILD_OUTPUT_META=y`. Without it Zephyr's top-level
`CMakeLists.txt` actively deletes the meta file, with the comment "Prevent spdx
to use invalid data".

`sbom_build.sh` passes `-DCONFIG_BUILD_OUTPUT_META=y` on the `west build`
command line. This mirrors Zephyr's own SBOM test at
`tests/application_development/software_bill_of_materials/`, which sets exactly
this one option.

### `west spdx` crashes with `AttributeError: 'NoneType'`

```
File ".../zspdx/walker.py", line 611, in collectTargetDependencies
    rd.ownerFileAbspath = pkg.targetBuildFile.abspath
AttributeError: 'NoneType' object has no attribute 'abspath'
```

A bug in zspdx at this Zephyr revision. `pkg.targetBuildFile` is only assigned
by `addBuildFile()`, which returns `None` when a target has no artifacts, yet
`collectTargetDependencies()` is called unconditionally.

Newer Zephyr guards the equivalent line with `if component.target_build_file:`.
`sbom_build.sh` applies the guard at runtime rather than forking the SDK. The
patch detects an already-patched file and fails loudly if the surrounding
source changes, so a Zephyr bump cannot silently turn it into a no-op.

Worth reporting upstream. The walker has clearly not been exercised against a
non-standard Zephyr integration like Matter's.

### The build fails with `#include <CHIPProjectConfig.h>` not found

You set `chip_device_project_config_include` in
`config/telink/chip-gn/args.gni`. The angle-bracket form needs an include path,
which Telink does not configure.

Do not add it. It is not needed for the SBOM pipeline, and the CMake side does
not define the macro at all -- so it would only fix half the problem. See the
red-herring note in
[`04-reproducible-builds.md`](04-reproducible-builds.md).

### `Filename too long` on a local checkout

Windows only, and only if you clone locally. `git config core.longpaths true`
works around it.

## The SBOM is missing the Matter stack

**Symptom:** `chip-module-sources` has `FilesAnalyzed: false` and zero files.

Check that the `Generate Matter source SBOM from the GN build` step ran and
succeeded. If it reports `ERROR: no compiled sources found`, the `.ninja_log`
intersection came up empty.

Two causes, both seen in practice:

**Paths not resolved against the entry's `directory`.** GN emits both the `-o`
value and the `file` field relative to that field, as
`../../../../src/lib/support/Base64.cpp`. Anything that resolves them against
the current working directory, or leaves them relative, produces an empty
intersection silently.

**The GN build did not run.** `.ninja_log` only exists after ninja has executed.
If the chip-gn step was skipped, there is nothing to read.

## Licenses come out as `NONE`

**Expected, up to a point.** zspdx reads only explicit
`SPDX-License-Identifier:` tags. openthread embeds the full BSD-3-Clause text
and Matter embeds the full Apache-2.0 boilerplate, so both come back `NONE`.

Raising zspdx's `numLinesScanned` does not help -- the tag is absent from the
whole file, not just past line 20.

`gn_sources_to_spdx.py` handles the Apache-2.0 case with a second pass matching
the grant sentence, and `module_licenses.json` covers openthread. The remainder
is what the review loop exists for.

**If the Matter sources report 0 of 288 licensed**, the Apache-2.0 boilerplate
pass is not running. Confirm the file's first 20 lines contain
`Licensed under the Apache License, Version 2.0`.

## The firmware is not reproducible

Check `SOURCE_DATE_EPOCH` first. The build step prints it:

```
=== SOURCE_DATE_EPOCH: 1794215038 (2026-11-09T09:03:58Z)
```

If that is missing, `sbom_build.sh` could not read the commit timestamp -- the
`git log` call failed, or the checkout is not a git repository.

If it is set, diff two builds before anything else. The method and the commands
are in [`04-reproducible-builds.md`](04-reproducible-builds.md); it is much
faster than reading build files.

## Artifacts are missing or a rerun lost them

**`gh run rerun` replaces the previous attempt's artifacts.** It re-runs the
same run, so there is only ever one artifact set. To keep two builds of the
same commit, use two separate `workflow_dispatch` runs.

**Two dispatches in a row cancel each other.** The workflow sets:

```yaml
concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: true
```

Overlapping runs on the same ref cancel. Wait for each to finish.

## Tooling problems on this machine

These are about the development environment, not the pipeline, but they waste
time if you do not know them.

**`github.com` is only reachable through a local proxy.** `git` has it
configured in `~/.gitconfig`; `curl` and `gh` do not, and fail with
"Connection was reset". Export `HTTPS_PROXY` for them.

**`gh api` paths get mangled by Git Bash.** `/user` becomes
`C:/Program Files/Git/user`. Set `MSYS_NO_PATHCONV=1`.

**Partial clones are unreliable over a flaky proxy.** `git clone
--filter=blob:none` fetches blobs on demand, and when those fetches fail
`git grep` returns empty results *silently* -- which is actively misleading.
Prefer the GitHub API for reading files out of large repositories.

**GitHub code search does not index forks.** Searching for a string in
`telink-semi/tl_zephyr` returns zero results regardless of whether it is there.
Search the upstream repository instead, or fetch files directly.

## Reading logs

`gh run view <id> --log` prints the workflow's own echo of each `run:` block
before the actual output, which makes grepping noisy. To find real output,
search for a string the script prints rather than one it contains, or filter the
echoed lines:

```bash
gh run view <id> --log > run.log
sed 's/^Build + SBOM (tl3238x)\t[A-Za-z &]*\t[0-9T:.Z-]* //' run.log
```

Also note that `run:` blocks execute under `sh -e`, so a `grep` that finds
nothing exits 1 and kills the step. Any grep in a diagnostic step needs
`|| true`.
