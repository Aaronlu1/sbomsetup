# 02 · Prerequisites

## 1. Shape of the target repository

It must be a `tl_matter` derivative. All four paths are required:

| Path | Purpose |
|---|---|
| `scripts/run_in_build_env.sh` | activates the pigweed build environment |
| `.github/actions/checkout-submodules-and-bootstrap/` | submodules + bootstrap |
| `examples/<app>/telink/` | the Zephyr application directory |
| `scripts/tools/telink/update_zephyr.py` | resets the container's tl_zephyr to the release revision |

If any is missing, use the standalone CI repository pattern in
[`09-adapting.md`](09-adapting.md).

---

## 2. GitHub Actions settings

| Item | Value |
|---|---|
| Settings → Actions → General | **Allow all actions and reusable workflows** |
| Default branch | must contain `.github/workflows/telink-build-sbom.yaml`, otherwise the Actions tab does not list it |
| Quota | private repos: 2000 minutes/month; one run takes 15–20 minutes |
| Branch protection | if the default branch is protected, merge the workflow via a PR |

---

## 3. Runtime environment

The container is pinned by digest:

```yaml
container:
  image: ghcr.io/project-chip/chip-build-telink@sha256:82a785fc...
  volumes:
    - "/:/runner-root-volume"
```

- The image is public; no login is needed.
- It ships Zephyr SDK 0.17.0, a pre-cloned `tl_zephyr`, all west modules and the
  hal_telink blobs.
- To bump the image, resolve the new digest through the OCI manifest API; do not
  use a mutable tag.

### Disk (the most common trap)

The runner has 14 GB by default. The repository's `maximize-runner-disk` action
only prunes when `/runner-root-volume` is mounted; otherwise it **exits 0
immediately**.

Keep this in the workflow:

```yaml
volumes:
  - "/:/runner-root-volume"
```

On success the log contains:

```
Freeing up runner disk space on /runner-root-volume
Done, freed up ~15GM of disk space
```

Without it, restoring the 1.5 GB bootstrap cache fails with
`No space left on device`.

---

## 4. Permissions and network

| Item | Requirement |
|---|---|
| Repository write access | able to push to the target branch |
| Container registry | access to `ghcr.io` (public) |
| External downloads | GitHub Releases (Trivy), pip, cipd (bootstrap) |
| Proxy | if the runner needs one, make sure `HTTPS_PROXY` reaches the container shell |

---

## 5. Where the baseline values come from

| Value | Source |
|---|---|
| Matter branch/commit | the "Code Bases" section of the release note |
| Zephyr commit | same; this is `TELINK_ZEPHYR_REV` |
| BLE SDK commit | determined by `tl_zephyr`'s `west.yml`; **do not configure it separately** |
| Container digest | the `docker-content-digest` of the image manifest on `ghcr.io` |

> Do not substitute "latest tag" for a commit: only builds of the same commit
> are comparable.
