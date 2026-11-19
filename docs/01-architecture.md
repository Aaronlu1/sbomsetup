# 01 · How the build-level SBOM is produced

## 1. Two kinds of SBOM

| | Scan-based (syft/scancode) | Build-based (this kit) |
|---|---|---|
| Input | a directory | an actual build |
| Sees | everything in the directory | what was compiled and linked |
| Blind to | which files reached the firmware | tools and libraries not used by the build |
| Good for | whole-package compliance, binaries and tools | "what is in this firmware" |

This kit is build-based: **an SBOM describes the product, not the developer's
machine.**

---

## 2. Data flow

```
GitHub Actions (chip-build-telink container)
        │
        ├─ checkout (fetch-depth: 1)
        ├─ submodules + pigweed bootstrap
        ├─ update_zephyr.py <zephyr-rev>     align Zephyr and west modules
        ├─ sbom_build.sh
        │     ├─ west spdx --init            register the CMake file-based API
        │     ├─ west build -DCONFIG_BUILD_OUTPUT_META=y
        │     ├─ patch zspdx walker          missing None guard
        │     └─ west spdx                   four SPDX documents
        ├─ gn_sources_to_spdx.py             .ninja_log ∩ compile_commands.json
        ├─ filter_sbom.py                    keep only modules in zephyr.map
        ├─ enrich_sbom.py                    fill fields, refresh references
        ├─ spdx_to_cyclonedx.py
        ├─ grype sbom                        vulnerability scan (report-only)
        └─ sbom_review.py + make_delivery.py
```

---

## 3. Why Matter sources need recovery

The Matter stack is built by GN through `ExternalProject_Add`, while
`west spdx` only walks the **CMake codemodel**. The whole protocol stack
therefore appears as one opaque package with `FilesAnalyzed: false` and a
single commit SHA.

`gn_sources_to_spdx.py` intersects two artefacts:

```
.ninja_log                 what ninja actually produced
      ∩
compile_commands.json      output .o -> source file
      =
sources that went into the build
```

Three plausible approaches that do not work (documented in the script):

| Approach | Why it fails |
|---|---|
| read `compile_commands.json` directly | lists what GN *could* build, including test targets never built |
| `gn desc` on the root target | the label does not resolve; requires the pigweed environment |
| filter by compiler | almost every entry uses the same compiler, so it discriminates nothing |

---

## 4. Why modules are filtered

`west update` fetches every module in the manifest and zspdx lists them all as
packages, but a TL3238 build links only a few.

`filter_sbom.py` keeps a module when:

- it has compiled files, **or**
- one of its archives appears in `zephyr.map`

Measured effect: `zephyr.spdx` 58 → 8 packages, review components 60 → 9.

> Do not filter on `FilesAnalyzed: false` alone: prebuilt-library modules carry
> the same flag but their `.a` may really be linked. Use the linker map.

---

## 5. Field enrichment

| Field | Source | Nature |
|---|---|---|
| `PackageSupplier` | VCS location, or the org in the purl | derived |
| `ExternalRef: purl` | derived from the VCS location | derived |
| `PackageLicenseDeclared` | aggregated file-level detections → `module_licenses.json` | the fallback is a **producer assertion** |

`modules-deps` documents have `PackageDownloadLocation: NOASSERTION` and only a
purl, so enrichment must fall back to the purl to find org/repo.

---

## 6. Cross-document references

`build.spdx` references `app.spdx` and `zephyr.spdx` through
`ExternalDocumentRef`, with SHA1 checksums. Enrichment rewrites those documents,
so the references **must be refreshed after enrichment**, or the delivered set
is internally inconsistent.

---

## 7. Outputs

| Output | Contents |
|---|---|
| 5 SPDX documents | app / zephyr / build / modules-deps / matter-sources |
| CycloneDX 1.6 | component level, for SCA tooling |
| Review material | `sbom-review.csv`, `sbom-gaps.md`, `prebuilt-binaries.txt` |
| Vulnerability report | `vuln/<document>.txt`, one Grype table per document |
| Delivery package | firmware + SBOM + manifest + checksums |
