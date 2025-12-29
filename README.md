# stockfish-downloader
[![posix helper](https://github.com/ppigazzini/stockfish-downloader/actions/workflows/posix_helper.yml/badge.svg)](https://github.com/ppigazzini/stockfish-downloader/actions/workflows/posix_helper.yml)
[![windows helper](https://github.com/ppigazzini/stockfish-downloader/actions/workflows/windows_helper.yml/badge.svg)](https://github.com/ppigazzini/stockfish-downloader/actions/workflows/windows_helper.yml)
[![docker helper](https://github.com/ppigazzini/stockfish-downloader/actions/workflows/docker_helper.yml/badge.svg)](https://github.com/ppigazzini/stockfish-downloader/actions/workflows/docker_helper.yml)

Scripts to download the [latest official pre-release/release](https://github.com/official-stockfish/Stockfish/releases) of the Stockfish chess engine built with the best compiling flags for your CPU.

## Supported Platforms
| Operating System | CPU | Script |
| --- | --- | --- |
| Linux | x86_64, x86_32, aarch64, armv7 | POSIX |
| Android | aarch64, armv7 | POSIX |
| macOS | x86_64, aarch64 | POSIX |
| Windows: WSL | x86_64 | POSIX |
| Windows: MSYS2, Cygwin | x86_64, aarch64 | POSIX |
| Windows | x86_64, aarch64 | Windows |

## Usage
- download the script for your Operating System, run it with a terminal or;
- simply copy and paste the content in a terminal and press "enter"
### Script POSIX
- shell: sh
- file: [posix_stockfish_downloader.sh](https://github.com/ppigazzini/stockfish-downloader/blob/main/posix_stockfish_downloader.sh)
- content:
  ```sh
  curl -fsSL https://raw.githubusercontent.com/ppigazzini/stockfish-downloader/main/posix_helper.sh | sh -s
  ```
- usage: copy and paste the script content in a shell, or download and run the script file
### Script Windows
- shell: terminal/powershell/cmd
- file: [windows_stockfish_downloader.cmd](https://github.com/ppigazzini/stockfish-downloader/blob/main/windows_stockfish_downloader.cmd)
- content:
  ```cmd
  powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "[System.Net.ServicePointManager]::SecurityProtocol = 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/ppigazzini/stockfish-downloader/main/windows_helper.ps1'))"
  ```
- usage: copy and paste the script content in a terminal/powershell/cmd or download and run the script file with a double click
- shortcuts to open a terminal in a folder:
  - mouse right click -> "Open in Terminal"
  - SHIFT + mouse right click -> "Open PowerShell window here"
  - write "powershell" in the file explore address bar
  - write "cmd" in the file explore address bar
