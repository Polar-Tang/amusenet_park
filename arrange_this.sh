#!/usr/bin/env bash
set -o pipefail

SRC_ROOT="/home/nautilus/Documents/combat_shit@v0/src"
DEST_ROOT="/home/nautilus/Documents/combat_shit@v0/node_modules/@quenty/abilities/Utils"
#CooldownController
sanitize_input() {
    local v; v="$1"
    if [[ -z "$v" || "$v" =~ [^A-Za-z0-9._-] ]]; then
        printf "Invalid filename: %s\n" "$v" >&2
        return 1
    fi
    printf "%s" "$v"
}

safe_find() {
    local base name out
    base="$1"
    name="$2"

    if ! out=$(find "$base" -type f -name "$name" 2>/dev/null); then
        printf "find failed in: %s\n" "$base" >&2
        return 1
    fi

    if [[ -z "$out" || "$out" =~ [[:space:]] ]]; then
        printf "File not found or invalid path: %s\n" "$name" >&2
        return 1
    fi

    printf "%s" "$out"
}

prepare_dest() {
    local dst dir
    dst="$1"
    dir=$(dirname "$dst")

    if ! mkdir -p "$dir"; then
        printf "Failed to create destination directory: %s\n" "$dir" >&2
        return 1
    fi
    printf "%s" "$dst"
}

move_file() {
    local src dst
    src="$1"
    dst="$2"

    if ! mv -- "$src" "$dst"; then
        printf "Failed to move %s to %s\n" "$src" "$dst" >&2
        return 1
    fi
}

main() {
    if [[ $# -ne 1 ]]; then
        printf "Usage: %s <filename>\n" "$0" >&2
        return 1
    fi

    local filename; filename=$(sanitize_input "$1") || return 1

    local src; src=$(safe_find "$SRC_ROOT" "$filename") || return 1

    local rel dest
    rel=${src#"$SRC_ROOT"/}
    if [[ -z "$rel" ]]; then
        printf "Failed to compute relative path\n" >&2
        return 1
    fi

    dest="$DEST_ROOT/$filename"
    dest=$(prepare_dest "$dest") || return 1

    if ! move_file "$src" "$dest"; then
        return 1
    fi

    printf "Moved: %s -> %s\n" "$src" "$dest"
}

main "$@"

