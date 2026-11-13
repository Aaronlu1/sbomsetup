# tl_matter SBOM kit

Build-level SBOM for a Telink Matter firmware: the SBOM is derived from the
sources that were actually compiled into the binary, not from whatever happens
to sit in the checkout.

This repository is a **kit**, not a library. It holds the files to add to a
`tl_matter` checkout plus the notes explaining why each one is the way it is.
`apply.sh` copies them in; everything else is documentation.

> **Example values**: branch names, commits, the board (`tl3238x`) and the app
> (`examples/lighting-app/telink`) below come from an internal validation setup
> and are examples only. Replace them with the values from your own release note.

---

## What you get

Every run uploads seven artifacts:

| Artifact | Contents | Audience |
|---|---|---|
| `telink-firmware` | `zephyr.bin`, `.elf`, `.map` | shipping / debugging |
| `telink-sbom-spdx-raw` | raw zspdx output, five SPDX documents | traceability |
| `telink-sbom-spdx-enriched` | the same five, NTIA fields filled in | **primary deliverable** |
| `telink-sbom-cyclonedx` | CycloneDX 1.6 JSON | SCA tooling |
| `telink-sbom-review` | review CSV / gap report / prebuilt list / Trivy report | internal review |
| `telink-sbom-delivery` | delivery zip (firmware + SBOM + MANIFEST + SHA256SUMS) | delivery pipeline |
| `telink-sbom-manifest` | 1.4 KB manifest + checksums | quick verification |

Measured on one `tl3238x` build: **130 packages, 9 real components, 454 Matter
source files**. The Matter stack is tracked file by file rather than as one
opaque package, and the build is reproducible (`zephyr.bin` is byte-identical
for the same commit).

---

## Quick start

```bash
# 1. Prepare a tl_matter checkout (fork or private mirror) on your release branch
git clone <your-repo> tl_matter && cd tl_matter
git checkout <release-branch>

# 2. Apply the kit (copies files only, nothing else is touched)
/path/to/sbomsetup/apply.sh .

# 3. Set your release baseline
$EDITOR .github/workflows/telink-build-sbom.yaml   # TELINK_ZEPHYR_REV / branches / board / app

# 4. Commit and push
git add -A && git commit -s -m "ci(telink): add SBOM pipeline"
git push origin <your-branch>
```

After pushing, open **Settings → Actions → General** and make sure
“Allow all actions and reusable workflows” is selected, then check the Actions tab.

See [`docs/00-quickstart.md`](docs/00-quickstart.md) for the detailed walkthrough.

---

## Repository layout

```
sbomsetup/
├── apply.sh                     apply / check / dry-run
├── AGENTS.md                    execution contract for AI assistants
├── docs/
│   ├── 00-quickstart.md         from zero to the first successful run
│   ├── 01-architecture.md       how the build-level SBOM is produced
│   ├── 02-prerequisites.md      repository, Actions, disk, container
│   ├── 03-workflow.md           the 20 workflow steps
│   ├── 04-scripts.md            script interfaces and gotchas
│   ├── 05-reproducibility.md    reproducible builds
│   ├── 06-troubleshooting.md    known problems and fixes
│   ├── 07-vulnerability-scan.md Trivy integration
│   ├── 08-delivery-bundle.md    delivery package and manifest
│   ├── 09-adapting.md           other branches / repos / CI platforms
│   └── 10-verification.md       how to verify the output
└── files/                       files copied into the target repository
    ├── .github/workflows/telink-build-sbom.yaml
    ├── scripts/tools/telink/*.py, *.sh, module_licenses.json
    ├── examples/platform/telink/build_info.cmake
    └── .gitattributes
```

---

## Requirements

- A repository derived from `tl_matter`, containing
  `scripts/run_in_build_env.sh`,
  `.github/actions/checkout-submodules-and-bootstrap`,
  `examples/*/telink/` and `scripts/tools/telink/update_zephyr.py`
- GitHub Actions (private repositories: 2000 minutes/month; one run takes
  15–20 minutes)
- No local toolchain: the build happens inside the `chip-build-telink` container

---

## Licence

Files under `files/` originate from Project CHIP and carry the Apache-2.0
header. The documentation in this repository is provided under the same terms.
