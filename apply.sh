#!/usr/bin/env bash
#
# Copy the SBOM kit into a tl_matter checkout.
#
# Usage:
#   ./apply.sh <target-repo> [--check] [--dry-run] [--force]
#
#   --check     compare only; report differences and exit 1 if any
#   --dry-run   print what would be copied, write nothing
#   --force     overwrite existing files without asking (default behaviour
#               already overwrites regular files; --force also replaces
#               .gitattributes instead of appending to it)
#
# Exit codes: 0 success, 1 bad usage / not a tl_matter checkout, 2 differences
# found in --check mode.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$KIT_DIR/files"

TARGET=""
MODE="apply"
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --check)   MODE="check" ;;
        --dry-run) MODE="dry-run" ;;
        --force)   FORCE=1 ;;
        -h|--help)
            sed -n '3,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "ERROR: unknown option $arg" >&2
            exit 1
            ;;
        *)
            if [[ -n "$TARGET" ]]; then
                echo "ERROR: more than one target given" >&2
                exit 1
            fi
            TARGET="$arg"
            ;;
    esac
done

TARGET="${TARGET:-.}"
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
    echo "ERROR: target directory does not exist" >&2
    exit 1
}

# --- sanity: does this look like a tl_matter checkout? ----------------------
missing=()
for probe in \
    scripts/run_in_build_env.sh \
    .github/actions/checkout-submodules-and-bootstrap \
    examples/platform/telink \
    scripts/tools/telink/update_zephyr.py
do
    [[ -e "$TARGET/$probe" ]] || missing+=("$probe")
done

if (( ${#missing[@]} )); then
    echo "ERROR: $TARGET does not look like a tl_matter checkout. Missing:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "If this is a different repository, see docs/09-adapting.md." >&2
    exit 1
fi

echo "kit    : $SRC"
echo "target : $TARGET"
echo "mode   : $MODE"
echo

# --- helpers ----------------------------------------------------------------
same_file() {
    [[ -f "$1" && -f "$2" ]] && cmp -s "$1" "$2"
}

append_gitattributes() {
    local target_file="$1"
    local rule='**/*.sh text eol=lf'
    if [[ ! -f "$target_file" ]]; then
        cp "$SRC/.gitattributes" "$target_file"
        echo "  added    .gitattributes"
        return
    fi
    if grep -qF "$rule" "$target_file"; then
        echo "  present  .gitattributes (rule already there)"
        return
    fi
    printf '\n# Shell scripts run inside the Linux build containers; a CRLF checkout\n# makes them fail with a confusing "bad interpreter" error.\n%s\n' "$rule" >> "$target_file"
    echo "  appended .gitattributes"
}

# --- walk the kit -----------------------------------------------------------
changed=0
copied=0

while IFS= read -r -d '' src; do
    rel="${src#"$SRC"/}"

    # .gitattributes is merged, never blindly overwritten.
    if [[ "$rel" == ".gitattributes" ]]; then
        if [[ "$MODE" == "check" ]]; then
            if [[ -f "$TARGET/.gitattributes" ]] && grep -qF '**/*.sh text eol=lf' "$TARGET/.gitattributes"; then
                echo "  ok       $rel"
            else
                echo "  differs  $rel"
                changed=$((changed + 1))
            fi
        elif [[ "$MODE" == "dry-run" ]]; then
            echo "  would merge $rel"
        elif (( FORCE )); then
            cp "$src" "$TARGET/$rel"
            echo "  copied   $rel"
        else
            append_gitattributes "$TARGET/$rel"
        fi
        continue
    fi

    dst="$TARGET/$rel"

    if same_file "$src" "$dst"; then
        echo "  ok       $rel"
        continue
    fi

    if [[ "$MODE" == "check" ]]; then
        echo "  differs  $rel"
        changed=$((changed + 1))
        continue
    fi

    if [[ "$MODE" == "dry-run" ]]; then
        echo "  would copy $rel"
        continue
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  copied   $rel"
    copied=$((copied + 1))
done < <(find "$SRC" -type f \
              -not -path '*/__pycache__/*' \
              -not -name '*.pyc' \
              -print0 | sort -z)

echo
case "$MODE" in
    check)
        if (( changed )); then
            echo "$changed file(s) differ. Re-run without --check to apply."
            exit 2
        fi
        echo "All kit files are up to date."
        ;;
    dry-run)
        echo "Dry run only; nothing written."
        ;;
    *)
        echo "$copied file(s) copied."
        echo
        echo "Next:"
        echo "  1. set TELINK_ZEPHYR_REV / branches / board+app in .github/workflows/telink-build-sbom.yaml"
        echo "  2. git add -A && git commit -s -m 'ci(telink): add SBOM pipeline'"
        echo "  3. enable Actions, push, and check the first run"
        ;;
esac
