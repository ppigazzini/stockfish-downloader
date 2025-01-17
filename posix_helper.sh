#!/bin/sh

# Find the last Stockfish release tag and set the download URL components
last_tag=$(curl -fsL https://api.github.com/repos/official-stockfish/Stockfish/releases | grep -m 1 'tag_name' | cut -d '"' -f 4)
base_url="https://github.com/official-stockfish/Stockfish/releases/download/$last_tag"

# Download and execute the official Stockfish script, capture the output
output=$(curl -fsSL https://raw.githubusercontent.com/official-stockfish/Stockfish/master/scripts/get_native_properties.sh | sh -s)

# Extract the second string from the output to set the file_name variable
file_name=$(echo "$output" | cut -d ' ' -f 2)

# Download the file with retry mechanism
printf "Downloading %s ...\n" "$file_name"
if ! curl -LO --retry 5 --retry-delay 5 --retry-all-errors "$base_url/$file_name"; then
    printf "Download failed after 5 attempts.\n"
    exit 1
fi
printf 'Done.\n'
