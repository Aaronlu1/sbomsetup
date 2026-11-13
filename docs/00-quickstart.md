# 00 · From zero to the first successful run

Goal: put a `tl_matter` derivative on the SBOM pipeline and produce SPDX,
CycloneDX and a delivery package in GitHub Actions.

Time: about 10 minutes to prepare, 15–60 minutes for the first run.

---

## 1. Prepare the repository

Two options:

| Option | How | Notes |
|---|---|---|
| Fork | fork `telink-semi/tl_matter` on GitHub | simplest; Actions is free for public repos |
| Private mirror | create a private repo and import or `git push --mirror` | you manage the minute quota |

Check out your release branch:

```bash
git clone <your-repo> tl_matter && cd tl_matter
git checkout <release-branch>
```

> The workflow file must exist on the **default branch**, otherwise GitHub does
> not list it in the Actions tab. If you only keep it on a feature branch,
> commit `.github/workflows/telink-build-sbom.yaml` to the default branch first.

---

## 2. Apply the kit

```bash
/path/to/sbomsetup/apply.sh .
```

It first checks that the target looks like a `tl_matter` checkout (four probe
files), then copies everything under `files/` preserving paths. Use `--check`
to compare only, `--dry-run` to print actions.

---

## 3. Set the baseline

Only three things in the workflow:

```yaml
env:
  TELINK_ZEPHYR_REV: <Zephyr commit from your release note>

on:
  push:
    branches:
      - 'ci/**'          # or your release branch
  workflow_dispatch:
    inputs:
      board: { default: <board> }
      app:   { default: <app-dir> }
```

The BLE SDK needs no separate setting: `tl_zephyr`'s `west.yml` already pins it.

---

## 4. Commit and push

```bash
git add -A
git commit -s -m "ci(telink): add SBOM pipeline"
git push origin <your-branch>
```

---

## 5. Enable Actions and watch the run

In **Settings → Actions → General**, select
“Allow all actions and reusable workflows”.

A job called **Telink Build + SBOM** should appear. First-run timing:

| Phase | Time |
|---|---|
| Pull container image (~4 GB) | 3–5 min |
| Submodules + bootstrap (cold) | 10–20 min |
| Sync Zephyr and west modules | 3–8 min |
| Build + `west spdx` | 5–10 min |
| Post-processing (filter / enrich / convert / scan / package) | 1–2 min |

---

## 6. Acceptance

A successful run produces seven artifacts:

```
telink-firmware
telink-sbom-spdx-raw
telink-sbom-spdx-enriched
telink-sbom-cyclonedx
telink-sbom-review
telink-sbom-delivery
telink-sbom-manifest
```

Download the small manifest first:

```bash
gh run download <run-id> -n telink-sbom-manifest -D ./manifest
cat ./manifest/manifest.json
```

Then the review material:

```bash
gh run download <run-id> -n telink-sbom-review -D ./review
cat ./review/review/sbom-gaps.md
```

“Awaiting human confirmation” should be a single digit. If it is much larger,
check that `filter_sbom.py` actually ran (see `docs/04-scripts.md`).

---

## 7. If the first run fails

1. Look up the log fragment in `docs/06-troubleshooting.md`.
2. Confirm `Maximize runner disk` printed `freed up ~15G`; if not, the disk
   mount is missing.
3. Confirm `Pin Telink Zephyr` did not emit
   `WARNING: west blobs fetch ... failed`.
4. Match the failing step against `docs/03-workflow.md`.
