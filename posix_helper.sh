#!/bin/sh

# Check if all the given flags are present in the CPU flags list
check_flags() {
    for flag; do
        printf '%s\n' "$flags" | grep -q -w "$flag" || return 1
    done
}

# Set the CPU flags list dropping underscores and points (sse4_1 or sse4.1)
get_flags() {
  flags=$(awk '/^flags[ \t]*:|^Features[ \t]*:/{gsub(/^flags[ \t]*:[ \t]*|^Features[ \t]*:[ \t]*|[_.]/, ""); line=$0} END{print line}' /proc/cpuinfo)
}

# Check for gcc march "znver1" or "znver2" https://en.wikichip.org/wiki/amd/cpuid
check_znver_1_2() {
  vendor_id=$(awk '/^vendor_id/{print $3; exit}' /proc/cpuinfo)
  cpu_family=$(awk '/^cpu family/{print $4; exit}' /proc/cpuinfo)
  [ "$vendor_id" = "AuthenticAMD" ] && [ "$cpu_family" = "23" ] && znver_1_2=true
}

# Set the file CPU x86_64 architecture
set_arch_x86_64() {
  if [ "$uname_s" != 'Darwin' ] && check_flags 'avx512vnni' 'avx512dq' 'avx512f' 'avx512bw' 'avx512vl'; then
    file_arch='x86-64-vnni256'
  elif [ "$uname_s" != 'Darwin' ] && check_flags 'avx512f' 'avx512bw'; then
    file_arch='x86-64-avx512'
  elif [ -z "${znver_1_2+1}" ] && check_flags 'bmi2'; then
    file_arch='x86-64-bmi2'
  elif check_flags 'avx2'; then
    file_arch='x86-64-avx2'
  elif check_flags 'sse41' && check_flags 'popcnt'; then
    file_arch='x86-64-sse41-popcnt'
  else
    file_arch='x86-64'
  fi
}

# Check the system type
uname_s=$(uname -s)
uname_m=$(uname -m)
case $uname_s in
  'Darwin') # Mac OSX system
    case $uname_m in
      'arm64')
        file_arch='x86-64-sse41-popcnt' # Supported by Rosetta 2
        ;;
      'x86_64')
        flags=$(sysctl -n machdep.cpu.features machdep.cpu.leaf7_features | tr '\n' ' ' | tr '[:upper:]' '[:lower:]' | tr -d '_.')
        set_arch_x86_64
        ;;
    esac
    file_os='macos'
    file_ext='tar'
    ;;
  'Linux') # Linux system
    get_flags
    case $uname_m in
      'x86_64')
        file_os='ubuntu'
        check_znver_1_2
        set_arch_x86_64
        ;;
      'i686')
        file_os='ubuntu'
        file_arch='x86-32'
        ;;
      'aarch64')
        file_os='android'
        file_arch='armv8'
        if check_flags 'asimddp'; then
          file_arch="$file_arch-dotprod"
        fi
        ;;
      'armv7'*)
        file_os='android'
        file_arch='armv7'
        if check_flags 'neon'; then
          file_arch="$file_arch-neon"
        fi
        ;;
      *) # Unsupported machine type, exit with error
        printf "Unsupported machine type: $uname_m\n"
        exit 1
        ;;
    esac
    file_ext='tar'
    ;;
  'CYGWIN'*|'MINGW'*|'MSYS'*) # Windows system with POSIX compatibility layer
    get_flags
    check_znver_1_2
    set_arch_x86_64
    file_os='windows'
    file_ext='zip'
    ;;
  *)
    # Unknown system type, exit with error
    printf "Unsupported system type: $uname_s\n"
    exit 1
    ;;
esac

# Find the last Stockfish release tag and set the download URL components
last_tag=$(curl -s https://api.github.com/repos/official-stockfish/Stockfish/releases | grep -m 1 'tag_name' | cut -d '"' -f 4)
base_url="https://github.com/official-stockfish/Stockfish/releases/download/$last_tag"
file_name="stockfish-$file_os-$file_arch.$file_ext"

# Download the file
printf "Downloading $file_name ...\n"
curl -JLo "$file_name" "$base_url/$file_name"
printf 'Done\n'
