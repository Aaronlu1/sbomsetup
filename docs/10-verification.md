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
| `grype` | `grype sbom:telink-matter.cdx.json` — non-zero findings are expected, and are the point of the CPE work (`07-vulnerability-scan.md`) |
| `trivy` | `trivy sbom telink-matter.cdx.json` — will report nothing useful; its SPDX decoder reads only purl |

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

`manifest.json`'s `commit` must equal the run's `github.sha`.

`manifest.json.buildConfig` must reference `sbom/build-config.txt`, and its
`sha256` must match that file in the bundle; `zephyrCommit` must equal
`TELINK_ZEPHYR_REV`. This is the evidence VEX statements rest on.

## 5. Per-run checklist

- [ ] all eight artifacts present
- [ ] `sbom-gaps.md` shows single-digit `NEEDS_REVIEW`
- [ ] `prebuilt-binaries.txt` lists only archives linked into the firmware
- [ ] `telink-sbom-vuln` holds one report per scanned document, and its
      per-document counts match what the detail lists underneath them
- [ ] no `CPE map skip` line in the log, and no `WARNING` about a CPE map entry
- [ ] `telink-matter.cdx.json` carries a `cpe` on the components the map covers
- [ ] enriched `ExternalDocumentRef` checksums match the actual files
- [ ] `sbomJsonFiles` entries parse as JSON, and `files.spdx.json` lists the
      same file count as the tag-value documents
- [ ] `vexFiles` are present, and every `not_affected` statement carries a
      `justification`
- [ ] `manifest.manualReview` matches `sbom/manual-review.csv`: same SHA-256,
      same row count, and `pending` counts rows still open (`pending` or
      `under_investigation`)
- [ ] every component without a CPE appears in `manual-review.csv` and is not
      described as clean while its conclusion is still open
- [ ] firmware timestamp equals the commit time
- [ ] every line of `SHA256SUMS` passes
