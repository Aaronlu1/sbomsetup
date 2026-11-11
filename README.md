# tl_matter SBOM setup

Everything needed to stand up an SBOM pipeline for
[`telink-semi/tl_matter`](https://github.com/telink-semi/tl_matter) in a GitHub
Actions fork, based on Zephyr's built-in `west spdx` generator.

This repository is a **kit**, not a library. It holds the twelve files that have
to be added to a tl_matter checkout, plus the notes explaining why each one is
the way it is.

## What you get

Each run of the pipeline uploads five artifacts:

| Artifact | Contents | Shipped |
| --- | --- | --- |
| `telink-firmware` | `zephyr.bin`, `.elf`, `.map` | yes |
| `telink-sbom-spdx-raw` | the five SPDX documents as emitted | no |
| `telink-sbom-spdx-enriched` | the same, NTIA-complete | **primary deliverable** |
| `telink-sbom-cyclonedx` | CycloneDX 1.6 JSON | for SCA tooling |
| `telink-sbom-review` | `sbom-review.csv`, `sbom-gaps.md` | for human review |

Measured on a `tl3238x` lighting-app build: **143 packages, 927 file entries**,
covering the Zephyr modules, the Matter protocol stack, and the application.

Two properties matter more than the counts:

- **The Matter stack is tracked**, not just Zephyr. zspdx alone sees the Matter
  stack as one opaque package with a commit SHA; this kit recovers the 288
  sources that were actually compiled into the firmware.
- **The build is reproducible.** Two runs of the same commit produce
  byte-identical `zephyr.bin` and `zephyr.elf`, so an SBOM can verify a shipped
  binary rather than only auditing which sources went into it.

## Quick start

Prerequisites: a GitHub account, and a fork of `telink-semi/tl_matter`.

```bash
# 1. Clone your fork on the branch the kit targets
git clone https://github.com/<you>/tl_matter.git
cd tl_matter
git checkout dev-tlk_v1.5

# 2. Apply the kit
/path/to/sbomsetup/apply.sh .

# 3. Review what changed, then push
git status
git add -A && git commit -m "ci(telink): add SBOM pipeline"
git push origin dev-tlk_v1.5
```

The workflow triggers on push and starts building. First run takes 30-60
minutes: it pulls a 4 GB container, fetches submodules, bootstraps, then builds.

Read [`docs/02-setup.md`](docs/02-setup.md) for the details, including what to
do if your fork is on a different upstream revision.

## The files

`files/` mirrors the layout inside tl_matter, so `apply.sh` is a straight copy.

| File | New? | What it does |
| --- | --- | --- |
| `.github/workflows/telink-build-sbom.yaml` | new | the pipeline |
| `scripts/tools/telink/sbom_build.sh` | new | build + `west spdx`, pins `SOURCE_DATE_EPOCH` |
| `scripts/tools/telink/gn_sources_to_spdx.py` | new | recovers the Matter sources GN compiled |
| `scripts/tools/telink/enrich_sbom.py` | new | fills supplier / license / purl |
| `scripts/tools/telink/spdx_to_cyclonedx.py` | new | SPDX to CycloneDX |
| `scripts/tools/telink/sbom_review.py` | new | review CSV, gap report, `--merge` |
| `scripts/tools/telink/module_licenses.json` | new | team-maintained license answers |
| `docs/platforms/telink/sbom.md` | new | policy doc: what the SBOM guarantees |
| `examples/platform/telink/build_info.cmake` | **modified** | makes `BUILD_TIMESTAMP` reproducible |
| `.gitattributes` | **modified** | forces LF for `*.sh` |
| `.github/.wordlist.txt` | **modified** | spellcheck terms |
| `docs/platforms/telink/index.md` | **modified** | adds the policy doc to the toctree |

The four modified files are small, additive edits. `docs/02-setup.md` lists the
exact lines if you would rather apply them by hand than overwrite.

## Documentation

| Document | Read it when |
| --- | --- |
| [`docs/01-overview.md`](docs/01-overview.md) | you want to understand how the pieces fit |
| [`docs/02-setup.md`](docs/02-setup.md) | you are setting this up |
| [`docs/03-review-workflow.md`](docs/03-review-workflow.md) | components need a license decision |
| [`docs/04-reproducible-builds.md`](docs/04-reproducible-builds.md) | you need to verify a shipped binary |
| [`docs/05-troubleshooting.md`](docs/05-troubleshooting.md) | something fails |

## Scope and known limits

- Targets **one** build (`tl3238x` lighting-app) on purpose. The upstream
  Telink workflow builds 23 targets; widening the matrix multiplies CI time
  without changing what the SBOM can express.
- **12 components ship with `NOASSERTION` licenses** until someone confirms
  them. That is a deliberate refusal to guess, not an oversight -- see
  [`docs/03-review-workflow.md`](docs/03-review-workflow.md).
- The `-off` suffix on some version strings is a Zephyr west state marker, not
  part of the version. Explained in the policy doc.
- `zephyr.map` differs between builds (GCC's LTO temp file names) and
  `libzephyr.a` differs at archive level. Neither reaches the shipped firmware.

## Base revision

The kit was developed against `dev-tlk_v1.5` at commit
`a97aad0e12ea553a38a1aedc14f59cd459e2ff1b`. The four modified files are the
only ones that could conflict on a different base.
