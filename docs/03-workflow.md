# 03 · The 23 workflow steps

The steps in `files/.github/workflows/telink-build-sbom.yaml`, in order:

| # | Step | Purpose | Typical failure |
|---:|---|---|---|
| 1 | Checkout | current commit only (`fetch-depth: 1`) | — |
| 2 | Checkout submodules & Bootstrap | submodules and the pigweed environment | `Could not find GN_EXECUTABLE` |
| 3 | Pin Telink Zephyr and modules to the release revision | `update_zephyr.py <rev>`; `west update` fetches modules and `tl_ble_sdk` | `west blobs fetch` checksum; `No such file` |
| 4 | Build example and generate SPDX SBOM | `sbom_build.sh`: init → build → patch → spdx | devicetree / GN / zspdx errors |
| 5 | Export mbedtls build configuration | writes `sbom/build-config.txt` and `sbom/build-symbols.txt` | `.config` missing (build did not configure) |
| 6 | Generate Matter source SBOM from the GN build | `gn_sources_to_spdx.py` | `sources emitted : 0` |
| 7 | Keep only modules that were actually linked | `filter_sbom.py` using `zephyr.map` | package count does not drop |
| 8 | Enrich SBOM for NTIA compliance | `enrich_sbom.py` | — |
| 9 | Convert SBOM to CycloneDX | `spdx_to_cyclonedx.py` | unexpected component count |
| 10 | Generate auxiliary SBOM views | `make_auxiliary.py`: SPDX JSON, file-level, dependency graph | JSON parse errors |
| 11 | Scan SBOM for vulnerabilities | `grype sbom` (report-only) | `could not install grype`; findings that do not add up |
| 12 | Generate SBOM review artefacts | `sbom_review.py` | — |
| 13 | List prebuilt archives linked into the firmware | intersect with `zephyr.map` | list far too long |
| 14 | Assemble delivery bundle | `make_delivery.py` | `skip (missing): ...` |
| 15 | Upload delivery manifest | small `manifest.json` + `SHA256SUMS` + `LICENSES/index.json` | — |
| 16 | Show SBOM summary | prints package / supplier / purl counts | — |
| 17 | Upload firmware | `zephyr.bin/.elf/.map` | — |
| 18 | Upload SBOM (raw) | four zspdx documents plus matter-sources | — |
| 19 | Upload SBOM (enriched) | NTIA-complete set | — |
| 20 | Upload SBOM (CycloneDX) | `telink-matter.cdx.json` | — |
| 21 | Upload SBOM review artefacts | review CSV, gap report, prebuilt list, config, symbols | — |
| 22 | Upload vulnerability report | one Grype table per document, `telink-sbom-vuln` | — |
| 23 | Upload delivery bundle | `telink-sbom-delivery.zip` | — |

---

## Triggers

```yaml
on:
  workflow_dispatch:      # manual, with board / app inputs
  push:
    branches: [ 'ci/**' ] # replace with your release branch
```

The `workflow_dispatch` inputs only apply to manual runs; push runs use the
defaults in the YAML.

To trigger from the command line:

```bash
gh workflow run telink-build-sbom.yaml \
  --repo <owner>/<repo> \
  --ref <branch>

# with explicit inputs
gh workflow run telink-build-sbom.yaml \
  --repo <owner>/<repo> \
  --ref <branch> \
  -f board=tl3238x_retention \
  -f app=examples/light-switch-app/telink
```

**Prefer this over pushing.** A push only fires when the changed files match the
workflow's `paths` filter, so a commit touching only documentation builds
nothing. Dispatching is also the only way to build the same commit a second
time without changing anything, which is how you check reproducibility --
`gh run rerun` cannot be used for that (see
[`06-troubleshooting.md`](06-troubleshooting.md), issue 22).

---

## Environment variables

| Variable | Purpose | Notes |
|---|---|---|
| `TELINK_ZEPHYR_REV` | Zephyr release commit | must match the Matter branch |
| `SBOM_NAMESPACE_PREFIX` | SPDX document namespace | already includes `github.repository` and the commit |
| `CHIP_NO_LOG_TIMESTAMPS` | no timestamps in firmware logs | removes a source of non-determinism |

---

## Success markers

| Step | What success looks like |
|---|---|
| Bootstrap | `Environment looks good` |
| Pin Zephyr | `west update` completes with no `WARNING: ... failed` |
| Build + spdx | `=== SBOM generation OK`, four non-empty documents |
| GN sources | `sources emitted : N` (N in the hundreds) |
| Filter | `zephyr.spdx: keep 8, drop 50`-style output |
| Grype | `grype version` output, then a findings count per document |
| Enrichment | `PackageSupplier: every value carries a typed prefix` |
| Delivery | `delivery: out/delivery (N payload files)` |
| Uploads | eight artifacts, none empty |

---

## Time budget

| Phase | Cold | Cached |
|---|---|---|
| Container image | 3–5 min | 1–2 min |
| Submodules + bootstrap | 10–20 min | 3–5 min |
| Zephyr + modules | 3–8 min | 3–8 min |
| Build + spdx | 5–10 min | 5–10 min |
| Post-processing | 1–2 min | 1–2 min |

Total 15–60 minutes depending on cache hits.
