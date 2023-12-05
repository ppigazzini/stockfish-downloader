$ProgressPreference = 'SilentlyContinue'

# Download Microsoft Sysinternals Coreinfo in the user's temp directory
# https://docs.microsoft.com/en-us/sysinternals/downloads/coreinfo
$temp_dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $temp_dir | Out-Null
$coreinfo_url = "https://download.sysinternals.com/files/Coreinfo.zip"
$coreinfo_path = Join-Path $temp_dir "Coreinfo.zip"
Invoke-WebRequest -Uri $coreinfo_url -OutFile $coreinfo_path
Expand-Archive -Path $coreinfo_path -DestinationPath $temp_dir

# Run Coreinfo and get the flags
$coreinfo_exe = Join-Path $temp_dir "Coreinfo.exe"
Start-Process -FilePath $coreinfo_exe -ArgumentList "/accepteula" -Wait
$coreinfo_output = & $coreinfo_exe -f | Out-String
$flags = $coreinfo_output -split "`n" | Where-Object { $_ -match "^([\w\.\-]+)\s+\*\s+.*$" } | ForEach-Object { $Matches[1] }

# Clean up the temporary directory
Remove-Item "$temp_dir" -Recurse

# Check for gcc march "znver1" or "znver2" https://en.wikichip.org/wiki/amd/cpuid
$processor = Get-WmiObject -Class Win32_Processor
$znver_1_2 = $processor.Manufacturer -eq "AuthenticAMD" -and $processor.Family -eq 23

# Find the CPU architecture
$file_arch = switch ($true) {
    ($flags -contains "AVX-512-VNNI" -and $flags -contains "AVX-512-DQ" -and $flags -contains "AVX-512-F" -and $flags -contains "AVX-512-BW" -and $flags -contains "AVX-512-VL") { "x86-64-vnni256"; break }
    ($flags -contains "AVX-512-F" -and $flags -contains "AVX-512-BW") { "x86-64-avx512"; break }
    ($flags -contains "BMI2" -and !$znver_1_2) { "x86-64-bmi2"; break }
    ($flags -contains "AVX2") { "x86-64-avx2"; break }
    ($flags -contains "SSE4.1" -and $flags -contains "POPCNT") { "x86-64-sse41-popcnt"; break }
    default { "x86-64" }
}

# Find the last Stockfish release tag and set the download URL components
$releases = Invoke-WebRequest -Uri "https://api.github.com/repos/official-stockfish/Stockfish/releases" | ConvertFrom-Json
$last_tag = $releases[0].tag_name
$base_url = "https://github.com/official-stockfish/Stockfish/releases/download/$last_tag"
$file_name = "stockfish-windows-$file_arch.zip"

# Download the file
Write-Output "Downloading $file_name ..."
Invoke-WebRequest -Uri "$base_url/$file_name" -OutFile "$file_name"
Write-Output "Done"

