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
| `could not install grype` / no `grype version` line | 20 |
| `CPE map skip` | 31 |
| Actions tab shows only “Get started” | 8, 9 |
| `was query directory created before cmake build ran?` | 25 |
| `invalid subvalue format for ... (no colon found)` | 26 |
| `No vulnerabilities found` for every document | 27 |

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
| 20 | The scanner step “succeeds” without producing a report: no findings table, green job | every failure branch of that step `exit 0`, on purpose -- a scanner problem must not cost the SBOM. The original instance was Trivy: the pinned version stopped existing, the URL 404'd, `tar` failed and the step skipped itself | make every skip print a reason and grep for it: `could not install grype` for the current scanner, `skipping` in general. Check the `telink-sbom-vuln` artifact exists, not just that the job is green |
| 21 | Trivy: `failed to unmarshal component type` | CycloneDX root component `type` is `firmware`, which Trivy rejects | emit `application` |
| 22 | Two builds of the same commit needed for a reproducibility check, but `gh run rerun` only ever yields one set of artifacts | `rerun` re-runs the same run and **replaces** the previous attempt's artifacts rather than keeping both | dispatch twice instead (`gh workflow run`), waiting for each to finish -- and see 24 |
| 23 | `gh run download -n telink-firmware` leaves an **empty directory and exits 0**, looking exactly like an expired artifact | the ~33 MB archive was truncated in transit (flaky proxy on the client side, not GitHub); a truncated zip has no central directory | fetch through the API with resume: `curl -sSL -C - -H "Authorization: Bearer $(gh auth token)" -o fw.zip https://api.github.com/repos/<owner>/<repo>/actions/artifacts/<id>/zip`, retrying until `unzip -t fw.zip` passes. A truncated zip is recognisable by its size being smaller than the artifacts API reports |
| 24 | Second `gh workflow run` cancels the first | the workflow sets `concurrency: cancel-in-progress: true` on the same ref | wait for each run to complete before dispatching the next |
| 26 | A scanner refuses to read the SBOM at all: `unable to decode spdx tag-value: invalid subvalue format for <name> (no colon found)` | **`PackageSupplier` needs a typed prefix.** SPDX 2.3 defines it as `[Person: | Organization: | NOASSERTION] <value>`; a bare name is a spec violation. One bad field makes the whole document undecodable, so every package loses its CPE and every scan reports zero | emit `PackageSupplier: Organization: <name>`, and assert that the count of typed values equals the package count. Hand-written test fixtures are written from the spec and therefore already have the correct form -- **only running a real build artifact exposes this** |
| 27 | Vulnerability scan reports zero findings for every C/C++ library | depends on the scanner. **Trivy's SPDX decoder reads only purl** -- `parseExternalReferences()` filters on `RefTypePurl` and skips everything else -- so it cannot see the CPE that zspdx emits, and `pkg:github/<org>/<repo>@<sha>` is in no ecosystem index | use **Grype**, whose Syft-based decoder has `extractCPEs()` and reads `cpe23Type`. Verified on a real SBOM: purl only gives "No vulnerabilities found"; the same package with its CPE gives 16 mbedtls CVEs. Scan only component-bearing documents -- `build.spdx` holds CMake targets with no version or identifier, and Grype matched one named `debug` to the npm package of that name |
| 25 | The CMake query was created but zspdx still bails: `cmake api reply directory .../.cmake/api/v1/reply does not exist` / `was query directory created before cmake build ran?` | **CMake decides which file-based API queries to answer before it processes any `CMakeLists.txt`.** Creating `<build>/.cmake/api/v1/query/codemodel-v2` from CMake code at configure time is therefore too late -- the file appears in the build directory and CMake never reads it. The CMake documentation's "replies are written when it runs to generate a build system" describes when replies are *written*, not when queries are *read* | keep `west spdx --init` **before** `west build`, which is what `sbom_build.sh` does. The query has to exist before CMake starts. The only in-build route is a `PreLoad.cmake` in each application source directory -- the route Zephyr's own SBOM test takes, and which it labels "an undocumented feature" |
| 28 | The per-document summary prints `0 findings` for a document whose detail output, printed immediately below it, lists 16 | the counter matched a positional pattern that assumed severity was the fourth column of Grype's table. The table is `name | installed | fixed-in | type | vulnerability | severity`, so severity is the sixth and the pattern matched nothing | count vulnerability IDs (`CVE-`/`GHSA-`), which is unambiguous. The failure was silent and in the direction that hides work |
| 29 | A component is plainly in the SBOM, yet the scan reports nothing for it | the purl points at `pkg:github/<org>/<repo>@<commit>`, which no advisory index contains, and no CPE was emitted for it. Only a module that declares `security.external-references` in its own `zephyr/module.yml` gets one -- in this dependency set that is mbedtls alone | add an entry to `module_cpes.json` (`07-vulnerability-scan.md` §5). Note that most components cannot have one at all; the file records why for each, and "absent from the report" is not the same as "clean" |
| 30 | The CPEs are in the enriched SPDX files but the delivered CycloneDX has none | `spdx_to_cyclonedx.py` read only `ExternalRef: PACKAGE_MANAGER purl`; a `SECURITY cpe23Type` line was parsed by nothing | carry it into the component's `cpe` field. Scanning the CycloneDX then returns the same findings as scanning the SPDX set -- measured, not assumed |
| 31 | `CPE map skip (revision moved): ...` | a mapped module was bumped to a new commit, so the CPE version no longer describes the code in the build. The entry is disabled rather than asserted | re-verify the version against the new revision and update the entry's `revision`, `version_source` and `evidence`. Until then that component is unscanned again |

---

## Methodological reminders

1. **A green job does not mean complete metadata.** Every non-critical step is
   written to skip with a printed reason. Search the log for `skipping`,
   `WARNING` and `skip (missing)` before trusting the result.
2. **Never judge by file name alone.** Both `libc.a` and `FilesAnalyzed: false`
   caused mistakes: the first produced false positives, the second would have
   dropped real components. Use the linker map or a content hash.
3. **Test against a real build artifact, not a fixture you wrote.** A fixture
   is written from the spec, so it already has the shape the spec requires and
   cannot reveal that the pipeline produces something else. Issue 26 was
   invisible to a hand-written SPDX file and appeared the moment a real
   enriched SBOM was scanned.
4. **A summary that reports zero is indistinguishable from a clean result.**
   Issue 27's first symptom was a counter printing "0 findings" next to a
   detail listing that showed 16. When a count and its detail disagree, the
   count is the thing to suspect. Count identifiers, not table columns --
   column position changes between tool versions and output formats.
