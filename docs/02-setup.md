# Setting it up

## What you need

- A GitHub account
- A fork of `telink-semi/tl_matter`
- Nothing else. All compilation happens in GitHub Actions, inside a container
  that already has the RISC-V toolchain, Zephyr and every module.

You do **not** need a local toolchain, `west`, or WSL. On Windows, the local
clone exists only to commit and push -- the Matter tree cannot even be checked
out there without `git config core.longpaths true`, because
`examples/chef/devices/rootnode_..._367e7cea91.matter` exceeds the 260
character path limit.

## Step 1: fork

Fork `telink-semi/tl_matter` to your account. Keep it **public** if you can:
GitHub Actions is free and unmetered on standard runners for public
repositories, and a full run takes 30-60 minutes. On a private fork the free
tier's 2000 minutes per month allows roughly twenty runs.

## Step 2: apply the kit

```bash
git clone https://github.com/<you>/tl_matter.git
cd tl_matter
git checkout dev-tlk_v1.5

/path/to/sbomsetup/apply.sh .
```

`apply.sh` copies the twelve files from `files/` into the checkout, preserving
paths. It prints what it did and refuses to run if the target does not look like
a tl_matter checkout.

Review the result before committing:

```bash
git status
git diff --stat
```

You should see seven added files and four modified.

## Step 3: push

```bash
git add -A
git commit -m "ci(telink): add SBOM pipeline"
git push origin dev-tlk_v1.5
```

The workflow triggers on push. If your fork has never run Actions, GitHub will
ask you to enable workflows the first time -- open the Actions tab and confirm.

## Step 4: watch it run

A first run takes 30-60 minutes:

| Phase | Roughly |
| --- | --- |
| pull the container image (~4 GB) | 3-5 min |
| checkout submodules | 5-15 min |
| bootstrap (cold; cached later) | 10-20 min |
| pin the Zephyr and BLE SDK revisions | 3-8 min |
| build + `west spdx` | 5-10 min |
| GN source recovery, enrichment, CycloneDX, review | under 1 min |

When it finishes, five artifacts are attached to the run.

## Applying the modified files by hand

`apply.sh` overwrites four existing files. They are small and additive, so you
can apply the edits manually instead if your fork has diverged.

**`.gitattributes`** -- append:

```
# Shell scripts run inside the Linux build containers; a CRLF checkout makes
# them fail with a confusing "bad interpreter" error. Keep them LF everywhere.
**/*.sh text eol=lf
```

**`.github/.wordlist.txt`** -- append these lines:

```
diffable
purl
mtimes
zspdx
sbom
spdx
cyclonedx
ntia
picolibc
littlefs
lvgl
zcbor
fatfs
percepio
noassertion
reproducible
```

**`docs/platforms/telink/index.md`** -- add `sbom` to the toctree and a link:

```
telink_getting_started
sbom
releases/telink_release_notes
```

```
[Telink - SBOM](./sbom.md)
```

**`examples/platform/telink/build_info.cmake`** -- replace the
`BUILD_TIMESTAMP` `execute_process` block with a version that honours
`SOURCE_DATE_EPOCH`. This is the change that makes builds reproducible; see
[`04-reproducible-builds.md`](04-reproducible-builds.md) for the full block.

## Adapting to a different upstream revision

The kit was developed against `dev-tlk_v1.5` at `a97aad0e`. On a newer base:

- The seven **added** files apply cleanly; nothing references revision-specific
  paths.
- The four **modified** files may conflict. The hand-edit lists above are the
  reliable route.
- Check `config/telink/chip-gn/args.gni` and
  `config/common/cmake/chip_gn_args.cmake` if the GN build fails -- the
  project-config include wiring has changed before.

## Bumping the toolchain container

The workflow pins the image by digest:

```yaml
image: ghcr.io/project-chip/chip-build-telink@sha256:144950e7...
```

A mutable tag would let upstream repoint the toolchain under a build, which
would make two SBOMs from the same commit disagree. To move to a newer image,
resolve the digest first:

```bash
TOK=$(curl -s "https://ghcr.io/token?scope=repository:project-chip/chip-build-telink:pull&service=ghcr.io" | jq -r .token)
curl -sI -H "Authorization: Bearer $TOK" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  https://ghcr.io/v2/project-chip/chip-build-telink/manifests/<TAG> \
  | grep -i docker-content-digest
```

The GitHub packages API needs the `read:packages` scope, which a default token
does not carry; the OCI registry API above works anonymously for public images.

## Building a different board or example

The workflow takes two `workflow_dispatch` inputs, `board` and `app`, both
defaulting to `tl3238x` and `examples/lighting-app/telink`.

Widening beyond one target multiplies CI time and changes nothing about what the
SBOM can express, which is why the default is a single build. If you do widen
it, note that `module_licenses.json` and `sbom-review.csv` are per-build: a
second board may pull in modules the first did not, and those will arrive as
unresolved.
