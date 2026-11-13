# 10 · Verifying the output

## 1. SPDX structure

### 1.1 Package verification code

SPDX 2.3 §7.9: `PackageVerificationCode` is the SHA1 of the sorted,
concatenated SHA1 values of every file in the package. Recompute it
independently:

```python
import hashlib
text = open("zephyr.spdx").read()
for block in text.split("##### Package: ")[1:]:
    lines = block.splitlines()
    vc = next((l.rsplit(":", 1)[1].strip() for l in lines
               if l.startswith("PackageVerificationCode:")), None)
    if not vc:
        continue
    sha1s = [l.rsplit(":", 1)[1].strip() for l in lines
             if l.startswith("FileChecksum: SHA1:")]
    calc = hashlib.sha1("".join(sorted(sha1s)).encode()).hexdigest()
    print(vc == calc, len(sha1s))
```

> Use `rsplit(":", 1)`: with `split(":", 1)`, the line
> `FileChecksum: SHA1: abc` yields `SHA1: abc` rather than the hash.

### 1.2 Reference integrity

```bash
grep '^ExternalDocumentRef:' enriched/build.spdx
sha1sum enriched/app.spdx enriched/zephyr.spdx
```

The checksums in the references must match the actual files in the enriched
directory.

### 1.3 Identifiers and relationships

- no duplicate `SPDXID` within a document
- every local `SPDXRef-*` used in a `Relationship` exists
- every `DocumentRef-*:SPDXRef-*` reference resolves in the target document

### 1.4 Standard tools

| Tool | Command |
|---|---|
| `pyspdxtools` | `pyspdxtools -i sbom.spdx` |
| `cyclonedx-cli` | `cyclonedx validate --input-file telink-matter.cdx.json` |
| `sbomqs` | `sbomqs score --category ntia telink-matter.cdx.json` |
| `trivy` | `trivy sbom telink-matter.cdx.json` |

## 2. Expected magnitudes

From one `tl3238x` build; use these to judge "normal", not as fixed values:

| Metric | Expectation |
|---|---|
| `zephyr.spdx` packages | single digits after filtering |
| `modules-deps.spdx` packages | single digits |
| `build.spdx` packages | around 100 (CMake targets) |
| `matter-sources.spdx` files | several hundred (454 in the example) |
| real components (with purl) | a handful to low teens |
| `prebuilt-binaries.txt` | 1–5 entries |
| `NEEDS_REVIEW` | single digits |

If `zephyr.spdx` has dozens of packages or the prebuilt list has thousands of
entries, `filter_sbom.py` or the list step did not take effect — check the log.

## 3. Reproducibility check

```bash
# same directory name, two clean builds
rm -rf out/repro-a && sbom_build.sh <board> <app> out/repro-a out/sbom-a
sha256sum out/repro-a/zephyr/zephyr.bin
rm -rf out/repro-a && sbom_build.sh <board> <app> out/repro-a out/sbom-a2
sha256sum out/repro-a/zephyr/zephyr.bin
```

The hashes must match. The timestamp in the firmware should equal the commit
time in UTC.

With different directory names the ELF differs (DWARF paths); compare after
`--strip-debug`.

## 4. Delivery package check

```bash
gh run download <run-id> -n telink-sbom-manifest -D ./manifest
cd <unpacked delivery>
sha256sum -c ./manifest/SHA256SUMS
```

`MANIFEST.json`'s `commit` must equal the run's `github.sha`.

## 5. Per-run checklist

- [ ] all seven artifacts present
- [ ] `sbom-gaps.md` shows single-digit `NEEDS_REVIEW`
- [ ] `prebuilt-binaries.txt` lists only archives linked into the firmware
- [ ] `trivy-sbom.json` parses and its version matches `TRIVY_VERSION`
- [ ] enriched `ExternalDocumentRef` checksums match the actual files
- [ ] firmware timestamp equals the commit time
- [ ] every line of `SHA256SUMS` passes
