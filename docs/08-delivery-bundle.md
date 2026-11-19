# 08 · Delivery package and manifest

## 1. Why a delivery package

The build-level SBOM is produced in CI, while the delivery process (another
GitLab pipeline, or a manual hand-off) needs something **self-describing,
verifiable and independent of the CI platform**.

`make_delivery.py` assembles it.

## 2. Structure

```
telink-sbom-delivery.zip
├── README.md                  status, usage, open items, firmware hashes
├── manifest.json              delivery status, SBOM metadata, counts, files[]
├── SHA256SUMS                 every payload file
├── firmware/zephyr.bin
├── firmware/zephyr.elf
├── sbom/{app,zephyr,build,modules-deps,matter-sources}.spdx   ← enriched
├── sbom/telink-matter.cdx.json
├── sbom/prebuilt-binaries.txt
├── sbom/vuln/{zephyr,modules-deps}.txt   ← Grype findings, if the scan ran

└── LICENSES/
    ├── README.md
    ├── index.json
    ├── <SPDX-ID>.txt          canonical text (standard-reference)
    └── declarations/<id>.txt  short declaration only
```

`observed/` is deliberately not produced: a build-level run has no scanner
evidence to cite.

## 3. manifest.json

```json
{
  "deliveryStatus": "analysis-preview | release-ready",
  "analysisValid": true,
  "releaseReady": false,
  "project": "<owner>/<repo>",
  "commit": "<sha>",
  "generated_utc": "2026-01-01T00:00:00Z",
  "generationContext": "Build-time SBOM from compiled sources and the linker map; ...",
  "sbomDocument": {
    "spdxVersion": "SPDX-2.3",
    "cdxVersion": "1.6",
    "lifecycle": "build",
    "signature_status": "not-signed"
  },
  "sbomFiles": ["sbom/app.spdx", "..."],
  "firmware": [{"path": "firmware/zephyr.bin", "sha256": "...", "bytes": 0}],
  "licenses": {
    "identified": 4,
    "standardReference": 4,
    "declarationOnly": 0,
    "textMissing": 0
  },
  "validationErrorCount": 0,
  "reviewWarningCount": 1,
  "files": [{"path": "README.md", "sha256": "..."}]
}
```

Rules:

- `releaseReady` is true only when `reviewWarningCount == 0` **and**
  `licenses.textMissing == 0`
- `deliveryStatus` is `release-ready` when `releaseReady` is true, otherwise
  `analysis-preview`
- `files[]` covers every payload file except `manifest.json` and `SHA256SUMS`

## 4. LICENSES/

The layout follows the internal `sdk-sbom` customer package so both kinds of
bundle can be handled the same way.

`index.json` entries:

```json
{
  "id": "Apache-2.0",
  "name": "Apache-2.0",
  "status": "standard-reference",
  "file": "Apache-2.0.txt",
  "url": "https://raw.githubusercontent.com/spdx/license-list-data/v3.26.0/text/Apache-2.0.txt",
  "sha256": "074e6e32..."
}
```

Statuses:

| Status | Meaning |
|---|---|
| `standard-reference` | canonical SPDX text; applicability is declared in the SBOM |
| `declaration-only` | `LicenseRef-*` or project terms: a short declaration, no full text |
| `text-missing` | the text could not be obtained; treat as a gap |

### Where the texts come from (A + B)

1. **Vendored**: `scripts/tools/telink/license-texts/` ships Apache-2.0,
   BSD-2-Clause, BSD-3-Clause, MIT, ISC, Zlib and MPL-2.0.
2. **Downloaded**: anything else is fetched from the pinned SPDX
   `license-list-data` tag, and the SHA-256 of the saved file is recorded.

A failed download becomes `text-missing`; nothing is invented.

### Expression parsing

SPDX expressions are split on uppercase, space-separated `AND` / `OR` / `WITH`.
Do not split case-insensitively: `GPL-2.0-or-later` contains `-or-`.

## 5. Manifest artifact

The delivery package is large, so a second artifact carries the small files:

```yaml
- name: Upload delivery manifest
  if: always()
  uses: actions/upload-artifact@v4
  with:
      name: telink-sbom-manifest
      path: |
          out/delivery/manifest.json
          out/delivery/SHA256SUMS
          out/delivery/LICENSES/index.json
```

Verify without downloading the big package:

```bash
gh run download <run-id> -n telink-sbom-manifest -D ./manifest
cd <unpacked delivery>
sha256sum -c ./manifest/SHA256SUMS
```

## 6. Feeding a scan-based pipeline

Taking an internal `sdk-sbom` (directory scanner) as the example, its
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
| build-level CVE triage | this kit's Grype scan (`sbom/vuln/`, `07-vulnerability-scan.md`) |

## 7. Suggested archiving

Name the directory `<version>-<short-sha>`:

```
tl_matter-<board>-<short-sha>/
├── README.md
├── manifest.json
├── SHA256SUMS
├── firmware/
├── sbom/
└── LICENSES/
```

Two builds of the same commit should give the same `zephyr.bin` hash, which
makes version-to-version comparison straightforward.
