#!/usr/bin/env bash
#
# Copy the SBOM pipeline files into a tl_matter checkout.
#
#   ./apply.sh /path/to/tl_matter
#
# The files under files/ mirror the layout inside tl_matter, so this is a
# straight copy. Four of them overwrite existing files; see docs/02-setup.md
# for the exact edits if you would rather apply those by hand.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$KIT_DIR/files"

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    echo "usage: $0 /path/to/tl_matter" >&2
    exit 2
fi
if [[ ! -d "$TARGET" ]]; then
    echo "ERROR: $TARGET is not a directory" >&2
    exit 1
fi

# Sanity-check the target so this cannot be pointed at the wrong tree.
missing=()
for probe in examples/platform/telink src/include/platform config/telink; do
    [[ -e "$TARGET/$probe" ]] || missing+=("$probe")
done
if (( ${#missing[@]} )); then
    echo "ERROR: $TARGET does not look like a tl_matter checkout." >&2
    echo "       missing: ${missing[*]}" >&2
    exit 1
fi

# Report which of the twelve are new and which overwrite.
new_files=()
overwrites=()
while IFS= read -r rel; do
    if [[ -e "$TARGET/$rel" ]]; then
        overwrites+=("$rel")
    else
        new_files+=("$rel")
    fi
done < <(cd "$SRC" && find . -type f | sed 's|^\./||' | sort)

echo "target : $TARGET"
echo "adding : ${#new_files[@]} file(s)"
for f in "${new_files[@]}";    do echo "   + $f"; done
echo "updating: ${#overwrites[@]} file(s)"
for f in "${overwrites[@]}";   do echo "   M $f"; done
echo

# Copy, preserving the LF endings the kit ships with. A CRLF shell script
# fails inside the Linux build container with a confusing "bad interpreter".
while IFS= read -r rel; do
    mkdir -p "$TARGET/$(dirname "$rel")"
    cp "$SRC/$rel" "$TARGET/$rel"
done < <(cd "$SRC" && find . -type f | sed 's|^\./||' | sort)

chmod +x "$TARGET/scripts/tools/telink/sbom_build.sh"

echo "done."
echo
echo "Next:"
echo "   cd $TARGET"
echo "   git status          # review before committing"
echo "   git add -A && git commit -m 'ci(telink): add SBOM pipeline'"
echo "   git push"
