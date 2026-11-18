# 06 · Known problems and fixes

Collected from actual runs, in the order they appeared. The numbers are for
cross-referencing, not severity.

## Look up by log fragment

| Log fragment | Issue |
|---|---|
| `Could not find GN_EXECUTABLE` / `pigweed_environment.gni` | 1 |
| `No such file or directory` for a header | 2 |
| `undefined node label` | 3 |
| `FileName: ../<something>/...` | 4 |
| `No space left on device` | 10 |
| `fetch_sdk.sh: No such file` | 11 |
| `west blobs fetch` + `checksum` | 12 |
| `Syntax error: redirection unexpected` | 16 |
| `failed to unmarshal component type` | 21 |
| `could not download trivy` / `not a valid tarball` | 20 |
| Actions tab shows only “Get started” | 8, 9 |
| `was query directory created before cmake build ran?` | 25 |

Two failures have **no log fragment at all**, because nothing prints:

- **23** -- an empty artifact directory with a zero exit code.
- **24** -- a run that was replaced by the next one.

Both are command-line side, not CI side. Check them before assuming a build
problem.

---

---

## Local environment

| # | Symptom | Root cause | Fix |
|---:|---|---|---|
| 1 | `activate.sh` silently does nothing; GN not found | pigweed's `env_root.txt` records the absolute checkout path; after moving the directory it no longer matches | move the checkout back, or run `./scripts/bootstrap.sh` again (10–20 min). **Never build through a symlinked path** |
| 2 | Build fails on a missing header | `include/zephyr` was emptied (tracked files missing) | `git checkout -- include/zephyr`; confirm `git ls-files -d \| wc -l` is 0 |
| 3 | devicetree: `undefined node label` | an application overlay references a node that only some boards define | use the board that provides it (e.g. an app needing retention features requires the retention board) |
| 4 | SPDX `FileName` is `../other/repo/...` | `--repo-root` pointed at a symlink; `os.path.abspath` does not resolve it | pass `$(realpath <repo>)` |
| 5 | Firmware carries the build time; two builds differ | `build_info.cmake` patch not applied | apply `files/examples/platform/telink/build_info.cmake` |
| 6 | Odd paths when the repository is reached through a share or symlink | build and file access used different paths | use real paths everywhere; do not build inside a shared folder |

## CI

| # | Symptom | Root cause | Fix |
|---:|---|---|---|
| 7 | New private repo has only an initial commit | GitHub Import did not import the history | push the full history from a local clone, or import again |
| 8 | No workflow runs after pushing | Actions disabled | Settings → Actions → General → Allow all actions |
| 9 | Actions tab still shows the onboarding page | the workflow file exists only on a feature branch; the tab reads the default branch | commit the workflow file to the default branch |
| 10 | `No space left on device` | 14 GB runner; `maximize-runner-disk` exits 0 unless `/runner-root-volume` is mounted | mount it: `volumes: ["/:/runner-root-volume"]`; success log contains `freed up ~15GM` |
| 11 | `fetch_sdk.sh: No such file` | the script only exists on some branches; release BLE SDK comes from `west.yml` | drop the explicit fetch step and rely on `west update` |
| 12 | `west blobs fetch` checksum mismatch | the blob mirror occasionally serves a truncated file (the published file matches the metadata) | retry three times; if it still fails, continue with a warning — a genuinely missing blob fails at link time |
| 13 | Dozens of vendor HALs in the SBOM | zspdx lists every module in the workspace | `filter_sbom.py` keeps only what the linker map references |
| 14 | Prebuilt list has over a thousand entries | scanning every `.a` on disk | intersect with the archives in `zephyr.map` |
| 15 | Prebuilt list is full of toolchain `libc.a` files | matching by basename only; the RISC-V link also uses `libc.a` | exclude `.environment/` and `out/`, emit relative paths |
| 16 | `Syntax error: redirection unexpected` | the runner executed the step with `sh`, which has no process substitution | rewrite in POSIX style (temp file + `while read`), set `shell: bash` |
| 17 | `modules-deps` components stay `NOASSERTION` | those packages have `PackageDownloadLocation: NOASSERTION` and only a purl | enrich falls back to the purl for supplier and licence lookup |
| 18 | Enriched `ExternalDocumentRef` checksums do not match | zspdx recorded the raw documents' checksums, then enrichment rewrote them | refresh the references at the end of enrichment |
| 19 | Namespace points at the kit author's repository; different commits collide | the default prefix was author-only and version-less | use `https://github.com/<repo>/spdx/<commit>` |
| 20 | Trivy step “succeeds” without producing a report | the pinned version no longer exists, the URL 404s, `tar` fails and the step skips | pin a version that exists; add `curl -f` and a `tar -tzf` pre-check |
| 21 | Trivy: `failed to unmarshal component type` | CycloneDX root component `type` is `firmware`, which Trivy rejects | emit `application` |
| 22 | Two builds of the same commit needed for a reproducibility check, but `gh run rerun` only ever yields one set of artifacts | `rerun` re-runs the same run and **replaces** the previous attempt's artifacts rather than keeping both | dispatch twice instead (`gh workflow run`), waiting for each to finish -- and see 24 |
| 23 | `gh run download -n telink-firmware` leaves an **empty directory and exits 0**, looking exactly like an expired artifact | the ~33 MB archive was truncated in transit (flaky proxy on the client side, not GitHub); a truncated zip has no central directory | fetch through the API with resume: `curl -sSL -C - -H "Authorization: Bearer $(gh auth token)" -o fw.zip https://api.github.com/repos/<owner>/<repo>/actions/artifacts/<id>/zip`, retrying until `unzip -t fw.zip` passes. A truncated zip is recognisable by its size being smaller than the artifacts API reports |
| 24 | Second `gh workflow run` cancels the first | the workflow sets `concurrency: cancel-in-progress: true` on the same ref | wait for each run to complete before dispatching the next |
| 25 | The CMake query was created but zspdx still bails: `cmake api reply directory .../.cmake/api/v1/reply does not exist` / `was query directory created before cmake build ran?` | **CMake decides which file-based API queries to answer before it processes any `CMakeLists.txt`.** Creating `<build>/.cmake/api/v1/query/codemodel-v2` from CMake code at configure time is therefore too late -- the file appears in the build directory and CMake never reads it. The CMake documentation's "replies are written when it runs to generate a build system" describes when replies are *written*, not when queries are *read* | keep `west spdx --init` **before** `west build`, which is what `sbom_build.sh` does. The query has to exist before CMake starts. The only in-build route is a `PreLoad.cmake` in each application source directory -- the route Zephyr's own SBOM test takes, and which it labels "an undocumented feature" |

---

## Two methodological reminders

1. **A green job does not mean complete metadata.** Every non-critical step is
   written to skip with a printed reason. Search the log for `skipping`,
   `WARNING` and `skip (missing)` before trusting the result.
2. **Never judge by file name alone.** Both `libc.a` and `FilesAnalyzed: false`
   caused mistakes: the first produced false positives, the second would have
   dropped real components. Use the linker map or a content hash.
