# 03 · The 20 workflow steps

The steps in `files/.github/workflows/telink-build-sbom.yaml`, in order:

| # | Step | Purpose | Typical failure |
|---:|---|---|---|
| 1 | Checkout | current commit only (`fetch-depth: 1`) | — |
| 2 | Checkout submodules & Bootstrap | submodules and the pigweed environment | `Could not find GN_EXECUTABLE` |
| 3 | Pin Telink Zephyr and modules to the release revision | `update_zephyr.py <rev>`; `west update` fetches modules and `tl_ble_sdk` | `west blobs fetch` checksum; `No such file` |
| 4 | Build example and generate SPDX SBOM | `sbom_build.sh`: init → build → patch → spdx | devicetree / GN / zspdx errors |
| 5 | Generate Matter source SBOM from the GN build | `gn_sources_to_spdx.py` | `sources emitted : 0` |
| 6 | Keep only modules that were actually linked | `filter_sbom.py` using `zephyr.map` | package count does not drop |
| 7 | Enrich SBOM for NTIA compliance | `enrich_sbom.py` | — |
| 8 | Convert SBOM to CycloneDX | `spdx_to_cyclonedx.py` | unexpected component count |
| 9 | Scan SBOM for vulnerabilities | `trivy sbom` (report-only) | `could not download trivy`; `unmarshal component type` |
| 10 | Generate SBOM review artefacts | `sbom_review.py` | — |
| 11 | List prebuilt archives linked into the firmware | intersect with `zephyr.map` | list far too long |
| 12 | Assemble delivery bundle | `make_delivery.py` | `skip (missing): ...` |
| 13 | Upload delivery manifest | small `manifest.json` + `SHA256SUMS` + `LICENSES/index.json` | — |
| 14 | Show SBOM summary | prints package / supplier / purl counts | — |
| 15 | Upload firmware | `zephyr.bin/.elf/.map` | — |
| 16 | Upload SBOM (raw) | four zspdx documents plus matter-sources | — |
| 17 | Upload SBOM (enriched) | NTIA-complete set | — |
| 18 | Upload SBOM (CycloneDX) | `telink-matter.cdx.json` | — |
| 19 | Upload SBOM review artefacts | review CSV, gap report, prebuilt list, Trivy report | — |
| 20 | Upload delivery bundle | `telink-sbom-delivery.zip` | — |

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

---

## Environment variables

| Variable | Purpose | Notes |
|---|---|---|
| `TELINK_ZEPHYR_REV` | Zephyr release commit | must match the Matter branch |
| `TRIVY_VERSION` | scanner version | the asset name contains the version; a wrong value 404s |
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
| Trivy | `Version: <TRIVY_VERSION>` and `Detected SBOM format` |
| Delivery | `delivery: out/delivery (N payload files)` |
| Uploads | six artifacts, none empty |

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
