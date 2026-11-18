# Operations guide

Day-to-day use: how to run the pipeline, read the results, and get the
artifacts out.

## Triggering a run

### The short answer

```bash
gh workflow run telink-build-sbom.yaml \
  --repo <you>/tl_matter \
  --ref ci/telink-sbom
```

Use this by default. `git push` also works but is conditional -- see below.

### All three ways

| Method | Command / action | When it fires |
| --- | --- | --- |
| **manual** | `gh workflow run telink-build-sbom.yaml --ref <branch>` | always, on any branch you name |
| **push** | `git push` | only when the changed files match the workflow's `paths` filter |
| **web** | Actions tab, pick the workflow, **Run workflow** | always |

### Why push does not always fire

The workflow declares:

```yaml
on:
    workflow_dispatch:
    push:
        branches: [dev-tlk_v1.5, 'ci/**']
        paths:
            - .github/workflows/telink-build-sbom.yaml
            - scripts/tools/telink/...
            - examples/platform/telink/**
```

A commit that only touches `docs/` matches nothing and triggers nothing. That
is deliberate -- documentation changes do not need a 40-minute rebuild -- but it
surprises people. **When in doubt, dispatch manually.** A manual run on the
same commit is also how you check reproducibility, since it produces a fresh,
independent build.

### Passing a different board or example

Both are `workflow_dispatch` inputs:

```bash
gh workflow run telink-build-sbom.yaml \
  --ref ci/telink-sbom \
  -f board=tl7218x \
  -f app=examples/light-all-clusters-app/telink
```

Defaults are `tl3238x` and `examples/lighting-app/telink`. Widening the matrix
multiplies CI time and does not change what the SBOM can express, so the default
is a single build.

## Watching a run

```bash
# What is running right now
gh run list --repo <you>/tl_matter --limit 5

# Follow one to completion
gh run watch <run-id> --repo <you>/tl_matter

# Step-level status
gh run view <run-id> --repo <you>/tl_matter
```

A run takes 30-60 minutes. Roughly: container pull 3-5 min, submodules 5-15,
bootstrap 10-20 cold (much less once cached), build 5-10.

### Reading the log

`gh run view --log` prints the workflow's own **echo of each `run:` block**
before the real output, which makes grepping noisy. Filter the echoed lines:

```bash
gh run view <run-id> --log > run.log
sed 's/^Build + SBOM (tl3238x)\t[A-Za-z &]*\t[0-9T:.Z-]* //' run.log
```

Two markers worth knowing:

```
=== SOURCE_DATE_EPOCH: 1794215038 (2026-11-09T09:03:58Z)
```
Confirms the reproducible-build pin took effect. If this line is missing, the
build is not reproducible.

```
objects in ninja log : 289
sources emitted      : 288
verification code    : 7eccd0ba45ebe9fe0fafa2802b2877d300d1affc
```
The Matter source recovery. `288` is the expected count for a `tl3238x`
lighting-app build, and **the verification code is a fingerprint of the whole
source set** -- compare it across runs to confirm nothing moved.

## Getting the artifacts

Five artifacts per run:

```bash
gh run download <run-id> --repo <you>/tl_matter -n telink-sbom-spdx-enriched -D out
```

Names: `telink-firmware`, `telink-sbom-spdx-raw`, `telink-sbom-spdx-enriched`,
`telink-sbom-cyclonedx`, `telink-sbom-review`.

### Large artifacts fail silently through a proxy

`telink-firmware` is about 33 MB compressed. Behind a flaky proxy,
`gh run download` can leave an **empty directory and exit 0** -- no error, no
partial file. It looks exactly like an expired artifact.

If that happens, fetch it through the API with resume:

```bash
TOKEN=$(gh auth token)
ARTIFACT_ID=$(gh api repos/<you>/tl_matter/actions/artifacts \
  --jq ".artifacts[] | select(.name==\"telink-firmware\") | .id")

# -C - resumes; a truncated transfer leaves a zip with no central directory,
# so retry until `unzip -t` passes
curl -sSL -C - -H "Authorization: Bearer $TOKEN" \
  -o fw.zip \
  "https://api.github.com/repos/<you>/tl_matter/actions/artifacts/$ARTIFACT_ID/zip"

unzip -t fw.zip && unzip fw.zip
```

A truncated zip is recognisable: `unzip` reports "cannot find zipfile directory"
and the file is smaller than the size shown by the artifacts API.

## The routine loop

```bash
# 1. Run
gh workflow run telink-build-sbom.yaml --ref ci/telink-sbom

# 2. Wait (or watch)
gh run watch <run-id>

# 3. Pull the review artifacts
gh run download <run-id> -n telink-sbom-review -D out

# 4. Fill confirmed_license in out/sbom-review.csv, then fold the answers back
python3 scripts/tools/telink/sbom_review.py --merge out/sbom-review.csv

# 5. Commit the updated map
git add scripts/tools/telink/module_licenses.json
git commit -m "sbom: confirm N licenses"
git push
```

Repeat until `sbom-review.csv` has no `NEEDS_REVIEW` rows. It converges: each
answer removes a row permanently.

See [`03-review-workflow.md`](03-review-workflow.md) for what the columns mean.

## Re-running and comparing

| Goal | Do this | Not this |
| --- | --- | --- |
| re-run a failed job | `gh run rerun <id> --failed` | -- |
| get a **second** build of the same commit | `gh workflow run ...` again, **after the first finishes** | `gh run rerun` -- it replaces the artifacts |
| compare two builds | download both, then `cmp` | -- |

Two dispatches in a row cancel each other: the workflow sets
`concurrency: cancel-in-progress: true` on the same ref. Wait for each to
finish.

## Checking reproducibility

```bash
# Build A
gh workflow run telink-build-sbom.yaml --ref ci/telink-sbom
# ... wait for it to complete ...

# Build B -- same commit
gh workflow run telink-build-sbom.yaml --ref ci/telink-sbom
# ... wait ...

# Compare
gh run download <A> -n telink-firmware -D a
gh run download <B> -n telink-firmware -D b
cmp a/zephyr.bin b/zephyr.bin && echo "reproducible"
cmp a/zephyr.elf b/zephyr.elf && echo "reproducible"
```

`zephyr.bin` and `zephyr.elf` should be byte-identical. `zephyr.map` will differ
(GCC's random LTO temp names) and that is expected -- see
[`04-reproducible-builds.md`](04-reproducible-builds.md).

## Cancelling

```bash
gh run cancel <run-id>
```

Dispatching again also cancels the in-flight run on the same ref, which is
usually the fastest way.

## Changing the pinned revisions

Two places, both in the workflow's `env:` block:

```yaml
TELINK_ZEPHYR_URL: https://github.com/telink-semi/tl_zephyr.git
TELINK_ZEPHYR_REV: 3b7996ad7645869aa2b1e6f2f16d56d03b8035a5
TELINK_BLE_SDK_URL: https://github.com/telink-semi/tl_ble_sdk_zephyr.git
TELINK_BLE_SDK_REV: eb0d12063db5606db8bca5526ce9b54c77c45797
```

Take the pair from the tl_matter release notes. Upstream CI pins a slightly
different tl_zephyr revision marked "for developers purpose"; this pipeline uses
the released pair so the SBOM has a reproducible baseline.

For the toolchain container, see
[`02-setup.md`](02-setup.md#bumping-the-toolchain-container).
