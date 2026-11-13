# 09 · Other branches, repositories and CI platforms

## 1. Another branch of the same repository

```bash
git worktree add ../tl_matter_v2 <release-branch> -b ci/sbom-v2
cd ../tl_matter_v2
/path/to/sbomsetup/apply.sh .
$EDITOR .github/workflows/telink-build-sbom.yaml   # TELINK_ZEPHYR_REV / branches
git add -A && git commit -s -m "ci(telink): SBOM pipeline"
git push origin ci/sbom-v2
```

Notes:

- branches starting with `ci/` work with the default trigger rules
- `update_zephyr.py` differs between baselines: some accept only a positional
  revision (`update_zephyr.py <hash>`), others also support
  `--sdk-repo/--sdk-hash`. **Follow the script in the target branch**
- `build_info.cmake` can be replaced with the kit version; the diff should be
  exactly +22/−5

## 2. Another board or application on the same branch

Use the `board` and `app` inputs on a manual run.

To build several targets in one run, use a matrix:

```yaml
strategy:
  matrix:
    include:
      - { board: tl3238x, app: examples/lighting-app/telink }
      - { board: tl7218x, app: examples/light-switch-app/telink }
```

Artifact names must include the parameters, or the jobs overwrite each other:

```yaml
name: telink-sbom-enriched-${{ matrix.board }}
```

## 3. Another repository

### 3.1 Suitability check

All four must exist (`apply.sh` checks them automatically):

```
scripts/run_in_build_env.sh
.github/actions/checkout-submodules-and-bootstrap/
examples/<app>/telink/
scripts/tools/telink/update_zephyr.py
```

If they do, follow section 1. If not, use the standalone CI repository pattern.

### 3.2 Standalone CI repository

When the target repository must not be modified, keep workflow and scripts in a
separate repository and check the target out as a subdirectory:

```yaml
steps:
  - uses: actions/checkout@v6          # the CI repository
  - uses: actions/checkout@v6          # the target repository
    with:
      repository: <owner>/tl_matter
      ref: <commit>
      path: src
      fetch-depth: 1
  - run: |
      cd src
      ./scripts/run_in_build_env.sh "bash $GITHUB_WORKSPACE/scripts/tools/telink/sbom_build.sh \
        <board> examples/lighting-app/telink out/build out/sbom"
```

Caveats:

- `--repo-root` must point at `src`
- artifact paths move accordingly
- this pattern does not trigger on commits to the target repository; use a
  schedule or manual dispatch

## 4. Changing the Zephyr baseline

- change `TELINK_ZEPHYR_REV` only
- the BLE SDK follows `west.yml`; do not configure it separately
- if a new Zephyr changes zspdx, the patch in `sbom_build.sh` **fails loudly**
  (`could not locate the expected line`). That means the patch point moved and
  needs review — do not ignore it

## 5. Several versions side by side

- one `ci/` branch per version
- `DocumentNamespace` includes the commit, so versions never collide
- `module_licenses.json` travels with the branch; shared entries can be
  cherry-picked
- private repository quota: 2000 minutes/month; 15–20 minutes per run

## 6. Other CI platforms (e.g. GitLab CI)

The kit is "a build plus a handful of Python scripts" and does not depend on
GitHub:

- use `ghcr.io/project-chip/chip-build-telink:<digest>` as the job image
- translate the workflow steps into `.gitlab-ci.yml` `script:` entries
- check runner disk: container plus bootstrap cache needs 15–20 GB free
- it complements rather than replaces a scan-based tool: one gives build-level
  evidence, the other whole-package compliance

## 7. New machine / new account checklist

| Item | Requirement |
|---|---|
| Container access | able to pull `ghcr.io/project-chip/chip-build-telink` |
| Repository rights | able to push to the target branch |
| Actions | enabled, and the default branch contains the workflow file |
| Disk | `/runner-root-volume` mounted so the prune action runs |
| Branch protection | if protected, merge the workflow via a PR |
