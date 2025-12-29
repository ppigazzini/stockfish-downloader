$ProgressPreference = 'SilentlyContinue'

$osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

# Coreinfo console executables (NOT the graphical CoreinfoEx series)
$coreinfo_exe_name = switch ($osArch) {
    ([System.Runtime.InteropServices.Architecture]::X86) { "Coreinfo.exe" }
    ([System.Runtime.InteropServices.Architecture]::X64) { "Coreinfo64.exe" }
    ([System.Runtime.InteropServices.Architecture]::Arm64) { "Coreinfo64a.exe" }
    default { "Coreinfo64.exe" }
}

$flags = @()

if ($osArch -eq [System.Runtime.InteropServices.Architecture]::X86) {
    Write-Output "Unsupported Windows OS architecture: x86 (32-bit)"
    exit 1
}
else {
    try {
        # Download Microsoft Sysinternals Coreinfo in the user's temp directory
        # https://docs.microsoft.com/en-us/sysinternals/downloads/coreinfo
        $temp_dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Force -Path $temp_dir | Out-Null
        $coreinfo_url = "https://download.sysinternals.com/files/Coreinfo.zip"
        $coreinfo_path = Join-Path $temp_dir "Coreinfo.zip"
        Invoke-WebRequest -Uri $coreinfo_url -OutFile $coreinfo_path -ErrorAction Stop
        Expand-Archive -Path $coreinfo_path -DestinationPath $temp_dir -ErrorAction Stop

        # Use the appropriate console Coreinfo executable for this architecture
        $coreinfo_exe = Join-Path $temp_dir $coreinfo_exe_name
        if (!(Test-Path -LiteralPath $coreinfo_exe)) {
            # Best-effort fallback: pick any Coreinfo*.exe present in the archive.
            $coreinfo_exe = (Get-ChildItem -LiteralPath $temp_dir -Filter "Coreinfo*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
        }
        if ([string]::IsNullOrWhiteSpace($coreinfo_exe) -or !(Test-Path -LiteralPath $coreinfo_exe)) {
            throw "Coreinfo executable not found in extracted archive"
        }

        try {
            $coreinfo_output_flags = & $coreinfo_exe /accepteula -f | ForEach-Object { $_ }
            $flags = ($coreinfo_output_flags | ForEach-Object {
                $l = $_.Trim()
                if ($l -match "\*") { ($l -split "\s+")[0] }
            }) | Sort-Object -Unique

            # Normalize flags like get_native_properties.sh: lowercase and strip separators
            # e.g. SSE4.1/SSE4_1 -> sse41, AVX-512-VNNI -> avx512vnni
            $flags = ($flags | ForEach-Object { $_.ToLowerInvariant() -replace "[-_.]", "" }) | Sort-Object -Unique
        }
        catch {
            # ARM64 Coreinfo may fail depending on runner/emulation; don't block downloads.
            Write-Output ("Coreinfo execution failed (continuing): " + $_.Exception.Message)
            $flags = @()
        }
    }
    finally {
        if ($null -ne $temp_dir -and (Test-Path -LiteralPath $temp_dir)) {
            Remove-Item -LiteralPath $temp_dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($osArch -eq [System.Runtime.InteropServices.Architecture]::Arm64) {
    # Matches Stockfish/scripts/get_native_properties.sh Windows ARM64 behavior.
    # We don't have a reliable way to detect dotprod vs non-dotprod on Windows.
    $file_arch = "armv8-dotprod"
}
else {
    # Check for gcc march "znver1" or "znver2" https://en.wikichip.org/wiki/amd/cpuid
    $processor = Get-WmiObject -Class Win32_Processor
    $znver_1_2 = $processor.Manufacturer -eq "AuthenticAMD" -and $processor.Family -eq 23

    # Find the CPU architecture
    $file_arch = switch ($true) {
        # Mirrors Stockfish/scripts/get_native_properties.sh set_arch_x86_64() ordering
        (
            $flags -contains "avx512f" -and
            $flags -contains "avx512cd" -and
            $flags -contains "avx512vl" -and
            $flags -contains "avx512dq" -and
            $flags -contains "avx512bw" -and
            $flags -contains "avx512ifma" -and
            $flags -contains "avx512vbmi" -and
            $flags -contains "avx512vbmi2" -and
            $flags -contains "avx512vpopcntdq" -and
            $flags -contains "avx512bitalg" -and
            $flags -contains "avx512vnni" -and
            $flags -contains "vpclmulqdq" -and
            $flags -contains "gfni" -and
            $flags -contains "vaes"
        ) { "x86-64-avx512icl"; break }
        (
            $flags -contains "avx512vnni" -and
            $flags -contains "avx512dq" -and
            $flags -contains "avx512f" -and
            $flags -contains "avx512bw" -and
            $flags -contains "avx512vl"
        ) { "x86-64-vnni512"; break }
        ($flags -contains "avx512f" -and $flags -contains "avx512bw") { "x86-64-avx512"; break }
        ($flags -contains "avxvnni") { "x86-64-avxvnni"; break }
        ($flags -contains "bmi2" -and !$znver_1_2) { "x86-64-bmi2"; break }
        ($flags -contains "avx2") { "x86-64-avx2"; break }
        ($flags -contains "sse41" -and $flags -contains "popcnt") { "x86-64-sse41-popcnt"; break }
        default { "x86-64" }
    }
}

# Find the last Stockfish release tag and set the download URL components
$github_headers = @{
    'User-Agent' = 'stockfish-downloader'
    'Accept'     = 'application/vnd.github+json'
}
$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/official-stockfish/Stockfish/releases" -Headers $github_headers -ErrorAction Stop
$last_tag = ($releases | Where-Object { -not $_.draft } | Select-Object -First 1).tag_name
$base_url = "https://github.com/official-stockfish/Stockfish/releases/download/$last_tag"
$file_name = "stockfish-windows-$file_arch.zip"

# Download the file
Write-Output "Downloading $base_url/$file_name ..."
$maxRetries = 5
$retryDelay = 5
$attempt = 0

while ($attempt -le $maxRetries) {
    try {
        Invoke-WebRequest -Uri "$base_url/$file_name" -OutFile "$file_name"
        Write-Output "Done."
        break
    } catch {
        if ($attempt -eq $maxRetries) {
            Write-Output "Download failed after $($maxRetries + 1) attempts."
            exit 1
        } else {
            Write-Output "Download failed. Will retry in $retryDelay seconds. ($($maxRetries - $attempt) retries left.)"
            Start-Sleep -Seconds $retryDelay
            $attempt++
        }
    }
}
