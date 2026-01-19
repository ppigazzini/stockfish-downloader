#!/bin/sh

# POSIX-strict mode
set -eu

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

warn() {
    printf '%s\n' "$*" >&2
}

json_first_string_field() {
    # Print the first occurrence of JSON string field $1 from stdin.
    # Best-effort: not a full JSON parser, but handles minified JSON.
    key=$1
    awk -v k="$key" '
        {
            if (match($0, "\"" k "\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")) {
                s = substr($0, RSTART, RLENGTH)
                sub(".*:[[:space:]]*\"", "", s)
                sub("\"$", "", s)
                print s
                exit
            }
        }
    '
}

json_all_string_field() {
    # Print all occurrences of JSON string field $1 from stdin.
    # Best-effort: not a full JSON parser.
    key=$1
    awk -v k="$key" '
        {
            line = $0
            while (match(line, "\"" k "\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")) {
                s = substr(line, RSTART, RLENGTH)
                sub(".*:[[:space:]]*\"", "", s)
                sub("\"$", "", s)
                print s
                line = substr(line, RSTART + RLENGTH)
            }
        }
    '
}

gh_api_get() {
    url=$1
    if [ -n "${GITHUB_TOKEN-}" ]; then
        curl -fsSL \
            --retry 5 --retry-delay 2 --retry-all-errors \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            -H "User-Agent: stockfish-downloader" \
            "$url"
    else
        curl -fsSL \
            --retry 5 --retry-delay 2 --retry-all-errors \
            -H "Accept: application/vnd.github+json" \
            -H "User-Agent: stockfish-downloader" \
            "$url"
    fi
}

download_with_retry() {
    url=$1
    curl -fJLO --retry 5 --retry-delay 5 --retry-all-errors "$url"
}

# Read a GitHub release JSON from stdin and print values of JSON "name" fields.
# Note: best-effort extractor; callers should filter.
list_release_asset_names() {
    json_all_string_field name
}

set_asset_triplet() {
    uname_s=$(uname -s 2>/dev/null || printf '%s' unknown)
    uname_m=$(uname -m 2>/dev/null || printf '%s' unknown)

    file_arch=$true_arch
    file_ext=tar

    case $uname_s in
        Darwin)
            file_os=macos
            file_ext=tar
            case $uname_m in
                arm64)
                    file_arch=m1-apple-silicon
                    ;;
                x86_64)
                    if [ "$true_arch" = "x86-64-avx512" ]; then
                        file_arch=x86-64-bmi2
                    fi
                    ;;
                *) : ;;
            esac
            ;;
        Linux)
            file_ext=tar
            case $uname_m in
                x86_64)
                    file_os=ubuntu
                    ;;
                i686)
                    file_os=ubuntu
                    # Legacy behavior: force 32-bit x86 asset name.
                    true_arch=x86-32
                    file_arch=x86-32
                    ;;
                ppc64*)
                    file_os=ubuntu
                    ;;
                aarch64)
                    file_os=android
                    ;;
                armv7*)
                    file_os=android
                    ;;
                loongarch64*)
                    file_os=linux
                    ;;
                *)
                    die "Unsupported machine type: $uname_m"
                    ;;
            esac
            ;;
        MINGW*ARM64*)
            file_os=windows
            file_ext=zip
            # Windows ARM64 (MSYS2/MinGW)
            # Can't reliably detect ARM CPU features here.
            true_arch=armv8-dotprod
            file_arch=armv8-dotprod
            ;;
        CYGWIN*|MINGW*|MSYS*)
            file_os=windows
            file_ext=zip
            ;;
        *)
            die "Unsupported system type: $uname_s"
            ;;
    esac
}

# Retrieve the latest tag from the GitHub API (retry up to 5 times).
attempt=0
last_tag=""
while [ "$attempt" -lt 5 ]; do
    releases_json=$(gh_api_get "https://api.github.com/repos/official-stockfish/Stockfish/releases?per_page=1" || :)
    last_tag=$(printf '%s\n' "$releases_json" | json_first_string_field tag_name || :)
    [ -n "$last_tag" ] && break
    attempt=$((attempt + 1))
    sleep 5
done
if [ -z "$last_tag" ]; then
    die "GitHub API inspection failed after 5 attempts."
fi

base_url="https://github.com/official-stockfish/Stockfish/releases/download/$last_tag"

# Get the best ARCH supported by this CPU as expected by Stockfish's Makefile.
# Fetch the detector script pinned to the same release tag.
true_arch_raw=$(
    curl -fsSL "https://raw.githubusercontent.com/official-stockfish/Stockfish/$last_tag/scripts/get_native_properties.sh" | sh -s
) || {
    die "Failed to fetch/run upstream get_native_properties.sh."
}

# Upstream may output either:
#   - "<arch>\n" (new)
#   - "<arch> <asset>\n" (old)
# Always take the first token.
set -- $true_arch_raw
true_arch=${1-}
detected_arch=$true_arch

if [ -z "$true_arch" ]; then
    die "Failed to detect native ARCH."
fi

set_asset_triplet
file_name="stockfish-$file_os-$file_arch.$file_ext"

printf 'Detected ARCH: %s\n' "$detected_arch"
if [ "$true_arch" != "$detected_arch" ]; then
    warn "Overriding ARCH for asset selection: $true_arch"
fi
printf 'Downloading %s ...\n' "$base_url/$file_name"
if download_with_retry "$base_url/$file_name"; then
    printf 'Done.\n'
    exit 0
fi

# Fallback path: inspect the GitHub release JSON to report why the expected
# asset name is not available (strictly no auto-selection of a different asset).
printf '%s\n' "Direct download failed; discovering assets for $last_tag ..." >&2
release_json=$(gh_api_get "https://api.github.com/repos/official-stockfish/Stockfish/releases/tags/$last_tag" || :)
if [ -z "$release_json" ]; then
    die "Failed to query release assets."
fi

# Filter to Stockfish assets only.
asset_names=$(printf '%s\n' "$release_json" | list_release_asset_names | grep '^stockfish-' || :)

# Strict compatibility: do not try other OSes or other arch tiers.
# Only validate whether the expected asset exists in this release.
if printf '%s\n' "$asset_names" | grep -Fqx "$file_name"; then
    printf '%s\n' "Asset exists in release, but download failed: $file_name" >&2
    exit 1
fi

printf '%s\n' "Expected asset not found in release: $file_name" >&2
printf '%s\n' "Available assets for $file_os:" >&2
printf '%s\n' "$asset_names" | grep -E "^stockfish-$file_os-" >&2 || :
exit 1
