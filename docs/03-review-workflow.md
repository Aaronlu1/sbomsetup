# The license review loop

## Why a human has to be involved

The SBOM ships with components whose license nobody has confirmed. That is
deliberate: `enrich_sbom.py` derives a license where there is evidence and
leaves `NOASSERTION` where there is not. It never invents one, because a license
declaration is a legal statement.

The evidence is thin for a specific reason. zspdx reads only an explicit
`SPDX-License-Identifier:` tag, and several of the projects here do not use
tags:

| Project | What its files actually contain | Detected as |
| --- | --- | --- |
| openthread | the full 28-line BSD-3-Clause text | `NONE` |
| the Matter stack | the full Apache-2.0 boilerplate | `NONE` |
| telink_ble_sdk | proprietary code, no headers at all | `NONE` |

Two mitigations are already in place. `gn_sources_to_spdx.py` recognises the
Apache-2.0 grant sentence directly, which resolves 286 of the 288 Matter
sources it emits. `module_licenses.json` carries confirmed answers keyed by
repository. Everything else is left for a person.

## What the reviewer actually sees

`sbom-review.csv` has one row per **real component** -- the ones carrying a
purl. In a typical build that is 21 rows out of 143 packages.

The other 121 packages are CMake build targets (`drivers--gpio`, `kernel`,
`zephyr-pre0`, ...). They have no upstream project and no independent license,
so listing them would waste the reviewer's time. They are counted in
`sbom-gaps.md` so the exclusion is explicit rather than silent.

Of the 21 rows, around 12 typically need a decision:

| Component | Repository | Why it is unresolved |
| --- | --- | --- |
| `lzma-sources` | telink-semi/xz | XZ Utils is public domain OR LGPL-2.1-or-later depending on the file |
| `openthread-telink-lib-sources` | telink-semi/openthread_telink_lib | Telink fork of the OpenThread library |
| `nfc-st25dv-sources` | telink-semi/nfc_st25dv | Telink component |
| `telink-st25dv-sources` | telink-semi/tl_st25dv | Telink component |
| `tflite-micro-telink-sources` | telink-semi/tflite-micro-telink | Telink fork of TensorFlow Lite Micro |
| `fatfs-sources` | zephyrproject-rtos/fatfs | no LICENSE file the GitHub API can identify |
| `percepio-sources` | zephyrproject-rtos/percepio | no LICENSE file the GitHub API can identify |
| `picolibc-sources` | zephyrproject-rtos/picolibc | mix of BSD-2-Clause and MIT |
| `segger-sources` | zephyrproject-rtos/segger | no LICENSE file the GitHub API can identify |
| `tinycrypt-sources` | zephyrproject-rtos/tinycrypt | no LICENSE file the GitHub API can identify |
| `chip-module-sources` | your tl_matter fork | the Matter stack itself |
| `mbedtls-deps` | Mbed-TLS/mbedtls | duplicate view of mbedtls; see below |

The `notes` column says why each row is open, so the reviewer is not starting
from a blank page.

## The loop

```bash
# 1. Download telink-sbom-review from a run
# 2. Fill the confirmed_license column in sbom-review.csv
# 3. Fold the answers back
python3 scripts/tools/telink/sbom_review.py --merge sbom-review.csv

# 4. Commit the updated module_licenses.json
git add scripts/tools/telink/module_licenses.json
git commit -m "sbom: confirm licenses for fatfs, segger"
git push
```

The next run resolves those components and the review list shrinks.

**Human input is a one-off cost that decreases over time.** Once every component
is confirmed the list stays empty unless a new module appears.

## Why CSV and not a spreadsheet

The review record is itself what an audit examines, so it has to be diffable in
a pull request. A binary `.xlsx` shows up as "cannot compare" and loses that
property entirely. CSV opens in Excel with a double-click and still diffs.

## Two details that are easy to get wrong

**`confirmed_license` is left blank even for resolved rows.** The column is the
reviewer's input and nothing else. Pre-filling it would make `--merge` write
auto-derived values into `module_licenses.json`, bloating the map with entries
zspdx already handles.

**`mbedtls` appears twice with different purls.** zspdx reports it as
`zephyrproject-rtos/mbedtls` (the Zephyr module, which resolves) and as
`Mbed-TLS/mbedtls` (upstream, from `modules-deps.spdx`). Same code, same
license: `Apache-2.0 OR GPL-2.0-or-later`. Noted in `needs_review` so the
reviewer is not left guessing.

## Reading `sbom-gaps.md`

Generated alongside the CSV, this is the summary to read first. It states the
scope (packages, real components, build targets excluded), the NTIA coverage,
and the open items with their reasons.

## A note on what `NOASSERTION` does not mean

`NOASSERTION` in a package field means *we are not asserting a license*, not
*this has no license*. The distinction matters when explaining the output to an
auditor: the correct answer to "why is this NOASSERTION" is usually "it is a
CMake build target with no independent license to declare", not "we do not
know".
