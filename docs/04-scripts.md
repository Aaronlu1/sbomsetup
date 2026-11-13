# 04 · Script interfaces and gotchas

All scripts live in the target repository under `scripts/tools/telink/`.

| Script | Purpose | Input | Output |
|---|---|---|---|
| `sbom_build.sh` | build + zspdx | board / app / build dir / sbom dir | four SPDX documents |
| `gn_sources_to_spdx.py` | recover GN-compiled Matter sources | `.ninja_log`, `compile_commands.json` | `matter-sources.spdx` |
| `filter_sbom.py` | drop modules that were not linked | sbom dir, `zephyr.map` | rewrites zephyr / modules-deps in place |
| `enrich_sbom.py` | supplier / licence / purl, refresh references | sbom dir | `enriched/*.spdx` |
| `spdx_to_cyclonedx.py` | convert to CycloneDX 1.6 | enriched dir | `*.cdx.json` |
| `sbom_review.py` | review artefacts | enriched dir | `sbom-review.csv`, `sbom-gaps.md` |
| `make_delivery.py` | assemble the delivery package | build / sbom dirs | `delivery/`, zip |

---

## sbom_build.sh

```bash
sbom_build.sh <board> <app-dir> <build-dir> <sbom-dir>
```

It must be invoked through `scripts/run_in_build_env.sh` (the pigweed
environment is required):

```bash
./scripts/run_in_build_env.sh "bash scripts/tools/telink/sbom_build.sh \
    tl3238x examples/lighting-app/telink out/build out/sbom"
```

Internally:

1. derives `SOURCE_DATE_EPOCH` from `git log -1 --format=%ct`
2. `west spdx --init` — **must run before CMake configures**
3. `west build ... -- -DCONFIG_BUILD_OUTPUT_META=y`
4. reads `KERNEL_META_PATH` from `CMakeCache.txt` and checks the file exists
5. patches the zspdx `walker.py` with a `None` guard
6. runs `west spdx` and verifies the four documents are non-empty

Gotchas:

- without `CONFIG_BUILD_OUTPUT_META=y`, Zephyr deletes the meta file
- the meta file is `zephyr.meta`, not `zephyr_meta.yml` as the error message says
- if the patch point is missing, the script **fails loudly** — the zspdx
  implementation changed and the patch needs review

---

## gn_sources_to_spdx.py

```bash
gn_sources_to_spdx.py --ninja-log <gn-out>/.ninja_log \
                      --compile-db <gn-out>/compile_commands.json \
                      --repo-root <repo> --out <file.spdx> \
                      [--purl ...] [--download-location ...] \
                      [--version ...] [--namespace ...]
```

Gotchas:

- `--repo-root` must be a `realpath`. If the repository is reached through a
  symlink, `os.path.abspath` does not resolve it while the compile database
  contains real paths, so every `FileName` becomes `../other/repo/...`
- GN's `-o` and `file` fields are relative to the entry's own `directory`;
  resolving them anywhere else silently yields no matches
- Matter sources have no `SPDX-License-Identifier`; the script matches the
  Apache-2.0 grant sentence on a second pass

---

## filter_sbom.py

```bash
filter_sbom.py --sbom-dir <dir> --map <build>/zephyr/zephyr.map [--dry-run]
```

- keeps a module when it has files **or** one of its archives appears in the map
- recomputes `build.spdx`'s `ExternalDocumentRef` checksums and removes dangling
  relationships
- `--dry-run` prints keep/drop counts without writing

Do not use `FilesAnalyzed: false` as the only criterion: prebuilt-library modules
carry the same flag but may really be linked.

---

## enrich_sbom.py

```bash
enrich_sbom.py <sbom-dir> [--license-map module_licenses.json] [--default-supplier NAME]
```

- supplier: VCS location → purl → default
- licence: existing conclusion → aggregated file-level licences (AND-joined on
  conflict) → `module_licenses.json`
- after all documents are written, refreshes `build.spdx`'s external references
- idempotent

---

## spdx_to_cyclonedx.py

```bash
spdx_to_cyclonedx.py <enriched-dir> -o <out.cdx.json>
```

Gotcha: the root component type is `application`. CycloneDX 1.6's `firmware`
type is rejected by Trivy's decoder (`failed to unmarshal component type`),
which makes the whole document unscannable.

---

## sbom_review.py

```bash
sbom_review.py <enriched-dir> --out-dir <review-dir>
sbom_review.py --merge <filled.csv>   # write answers back to module_licenses.json
```

Only packages with a purl are listed as components; build-internal CMake targets
are counted but not listed.

---

## make_delivery.py

```bash
make_delivery.py [--build-dir DIR] [--sbom-dir DIR] [--out-dir DIR] [--zip FILE]
```

Assembles `firmware/`, `sbom/`, `LICENSES/`, `README.md`, `manifest.json` and `SHA256SUMS`. Missing inputs
print `skip (missing)` rather than failing.

---

## module_licenses.json

```json
{
  "licenses":     { "<org>/<repo>": "<SPDX expression>" },
  "needs_review": { "<org>/<repo>": "<why it is unresolved>" }
}
```

- entries under `licenses` are applied automatically
- entries under `needs_review` are **not** applied; they only explain gaps
- use SPDX identifiers or expressions only; when unsure, leave the entry in
  `needs_review`
