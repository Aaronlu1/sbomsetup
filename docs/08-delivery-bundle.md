# 08 · Delivery package and manifest

## 1. Why a delivery package

The build-level SBOM is produced in CI, while the delivery process (another
GitLab pipeline, or a manual hand-off) needs something **self-describing,
verifiable and independent of the CI platform**.

`make_delivery.py` assembles it.

## 2. Structure

```
telink-sbom-delivery.zip
├── firmware/zephyr.bin
├── firmware/zephyr.elf
├── sbom/{app,zephyr,build,modules-deps,matter-sources}.spdx   ← enriched
├── sbom/telink-matter.cdx.json
├── sbom/prebuilt-binaries.txt
├── sbom/trivy-sbom.json
├── MANIFEST.json
└── SHA256SUMS
```

`MANIFEST.json`:

```json
{
  "project": "<owner>/<repo>",
  "commit": "<sha>",
  "generated_utc": "2026-01-01T00:00:00Z",
  "files": [
    {"path": "firmware/zephyr.bin", "sha256": "..."}
  ]
}
```

## 3. Design choices

| Choice | Reason |
|---|---|
| enriched SPDX only, no raw | raw is an intermediate artifact |
| no `.map` | debugging only, large, not needed for compliance |
| include `zephyr.elf` | field debugging needs it; costs ~30 MB in the zip |
| manifest both inside and as its own artifact | self-describing package, quick verification |

If the ELF is not needed, remove its entry from `SINGLE_FILES` in
`make_delivery.py`; the zip shrinks to a few MB.

## 4. Manifest artifact

The delivery package is large, so a second artifact carries the small files:

```yaml
- name: Upload delivery manifest
  if: always()
  uses: actions/upload-artifact@v4
  with:
      name: telink-sbom-manifest
      path: |
          out/delivery/MANIFEST.json
          out/delivery/SHA256SUMS
```

Verify the package without downloading it:

```bash
gh run download <run-id> -n telink-sbom-manifest -D ./manifest
cd <unpacked delivery>
sha256sum -c ./manifest/SHA256SUMS
```

## 5. Feeding a scan-based pipeline

Taking a typical internal `sdk-sbom` (directory scanner) as the example, its
configuration **does not change**:

1. unpack the zip into the SDK's `sbom/build-level/` (an attachment; the scanner
   does not parse it)
2. add the libraries from `prebuilt-binaries.txt` to `binary_components` in
   `metadata.xlsx`
3. run the scanner as usual; its validation gate stays as it is

Division of labour:

| Capability | Provided by |
|---|---|
| whole-package scan, version/licence register, release gate | scan-based tool |
| exact "compiled into the firmware" source list and file hashes | this kit |
| reproducible-build evidence | this kit |
| whole-package CVE scan | scan-based tool |
| build-level CVE triage | this kit's Trivy |

## 6. Suggested archiving

Name the directory `<version>-<short-sha>`:

```
tl_matter-<board>-<short-sha>/
├── firmware/
├── sbom/
├── MANIFEST.json
└── SHA256SUMS
```

Two builds of the same commit should give the same `zephyr.bin` hash, which
makes version-to-version comparison straightforward.
