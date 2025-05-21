#!/bin/sh

# Retrieve the latest tag from the GitHub API
attempt=0
last_tag=""
while [ "$attempt" -lt 5 ]; do
    if [ -n "$GITHUB_TOKEN" ]; then
        printf "Using GitHub token for authentication.\n"
        last_tag=$(curl -fsL -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/official-stockfish/Stockfish/releases" | grep -m 1 'tag_name' | cut -d '"' -f4)
    else
        last_tag=$(curl -fsL "https://api.github.com/repos/official-stockfish/Stockfish/releases" | grep -m 1 'tag_name' | cut -d '"' -f4)
    fi
    if [ -n "$last_tag" ]; then
        break
    fi
    attempt=$(expr "$attempt" + 1)
    sleep 5
done
if [ -z "$last_tag" ]; then
    printf "GitHub API inspection failed after 5 attempts.\n" >&2
    exit 1
fi
base_url="https://github.com/official-stockfish/Stockfish/releases/download/$last_tag"

# Download and execute the official Stockfish script, capture the output
output=$(curl -fsSL "https://raw.githubusercontent.com/official-stockfish/Stockfish/master/scripts/get_native_properties.sh" | sh -s)

# Extract the second string from the output to set the file_name variable
file_name=$(echo "$output" | cut -d ' ' -f2)

# Download the file with retry mechanism
printf "Downloading %s ...\n" "$base_url/$file_name"
if ! curl -fJLO --retry 5 --retry-delay 5 --retry-all-errors "$base_url/$file_name"; then
    printf "Download failed after 5 attempts.\n" >&2
    exit 1
fi
printf 'Done.\n'
