# AGENTS.md — execution contract for AI assistants

This file explains **how to put a `tl_matter` repository on the SBOM pipeline**
using this kit. The goal is that an assistant can read the repository in a fixed
order, execute the steps, and verify the result without guessing.

---

## 1. Reading order

| # | File | Why |
|---:|---|---|
| 1 | `README.md` | what this is, what it produces |
| 2 | `docs/01-architecture.md` | why the SBOM is build-level, not scan-level |
| 3 | `docs/02-prerequisites.md` | what the target repository must provide |
| 4 | `docs/00-quickstart.md` | the actual procedure |
| 5 | `docs/03-workflow.md` | what each workflow step does |
| 6 | `docs/06-troubleshooting.md` | first stop when something fails |

`docs/04`–`05` and `07`–`10` are reference material; read them when the
corresponding topic comes up.

---

## 2. Hard rules

1. **Do not invent version numbers.** `TELINK_ZEPHYR_REV`, branch names and the
   container digest must come from the release note, `west.yml`, or an OCI
   manifest query.
2. **Do not silently skip failures.** Every “fail and `exit 0`” branch in the
   scripts prints a reason (`skipping ...`). Confirm these branches were not
   taken before declaring success.
3. **Do not edit generated SBOM documents.** Change the scripts under `files/`
   or `module_licenses.json`, then re-run the pipeline.
4. **Do not run `apply.sh` against a repository that is not the intended
   target.** It overwrites files with the same path.
5. **Do not commit build outputs, binaries or tokens.** Artifacts are
   distributed through GitHub Actions.

---

## 3. Procedure

### 3.1 Pre-flight checks

```bash
test -f scripts/run_in_build_env.sh
test -f .github/actions/checkout-submodules-and-bootstrap/action.yaml
test -d examples/lighting-app/telink
test -f scripts/tools/telink/update_zephyr.py
```

If any is missing, the repository is not a `tl_matter` derivative — use the
standalone CI repository pattern in `docs/09-adapting.md`.

### 3.2 Apply and validate

```bash
/path/to/sbomsetup/apply.sh <target> --check    # compare only, no writes
/path/to/sbomsetup/apply.sh <target> --dry-run  # print actions
/path/to/sbomsetup/apply.sh <target>            # copy files
```

After applying, validate:

```bash
python3 -c "import yaml;yaml.safe_load(open('<target>/.github/workflows/telink-build-sbom.yaml'))"
python3 -m py_compile <target>/scripts/tools/telink/*.py
```

### 3.3 Adjust the baseline

Only three things should change in the workflow:

| Value | Source |
|---|---|
| `TELINK_ZEPHYR_REV` | the Zephyr commit from the release note |
| `on.push.branches` | the branch you actually push (`ci/**` works as is) |
| `board` / `app` | your target board and application directory |

### 3.4 Push and first run

Confirm Actions is enabled, then push. The first run takes 15–60 minutes; the
first 10–20 minutes are normally spent in `Initialize containers` / `Bootstrap`.

### 3.5 Verify the result

```bash
gh run list --repo <owner>/<repo> -L 3
gh run download <run-id> --repo <owner>/<repo> -n telink-sbom-manifest -D ./manifest
```

Expected:

| Check | Expectation |
|---|---|
| Artifact count | 8 |
| `sbom-review.csv` | a handful of rows, `NEEDS_REVIEW` in single digits |
| `prebuilt-binaries.txt` | only archives actually linked (1–5 entries) |
| `telink-sbom-vuln` | one table per scanned document, counts agreeing with the detail below them, and no `CPE map skip` in the log |
| `SHA256SUMS` | matches the files in the delivery package line by line |

A scan that finds nothing for a component is **not** evidence that the
component is clean. Read `docs/07-vulnerability-scan.md` §4 before writing
anything about vulnerability status into a customer document.

---

## 4. Failure signatures

| Log fragment | Go to |
|---|---|
| `No space left on device` | `docs/02-prerequisites.md`, disk mount |
| `Could not find GN_EXECUTABLE` / `pigweed_environment.gni` | `docs/06-troubleshooting.md` #1 |
| `west blobs fetch` checksum | `docs/06-troubleshooting.md` #12 |
| `fetch_sdk.sh: No such file` | `docs/06-troubleshooting.md` #11 |
| `failed to unmarshal component type` | `docs/07-vulnerability-scan.md` |
| `could not install grype` | `docs/07-vulnerability-scan.md`, network |
| `CPE map skip` | `docs/06-troubleshooting.md` #31 |
| `Syntax error: redirection unexpected` | `docs/06-troubleshooting.md` #16 |
| SPDX path `../<repo>/...` | `docs/04-scripts.md`, `--repo-root` |

---

## 5. Things you do not need to do

- Edit SPDX or CycloneDX documents by hand
- Install Zephyr or a toolchain locally
- Push Zephyr into the target repository (the container ships a pre-cloned copy)
- Write a licence entry for every module (`module_licenses.json` only needs the
  entries a human has confirmed)
