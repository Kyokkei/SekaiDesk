# Contributing to SekaiDesk

Thanks for checking out **SekaiDesk**! This project is primarily maintained by a solo developer, so PRs, bug reports, and **Windows 11 / multi-monitor compatibility testing** are especially appreciated.

## Building Locally (Windows)

Requirements:
- **CMake 3.21+** and **Ninja**
- **C++20** compiler (MinGW-w64 / LLVM-MinGW recommended)
- **Qt 6.8+** (`Core`, `Gui`, `Qml`, `Quick`, `Network`, plus QML modules `Svg`, `QuickControls2`, `ShaderEffect`)

```powershell
git clone https://github.com/Kyokkei/SekaiDesk.git
cd SekaiDesk
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

To run standalone or package with Qt runtime DLLs:

```powershell
New-Item -ItemType Directory -Force installer/stage | Out-Null
Copy-Item build/SekaiDesk.exe installer/stage/
windeployqt --release --qmldir qml installer/stage/SekaiDesk.exe
```

## Safe Testing

Launch an isolated instance alongside your running shell without colliding with its single-instance mutex:

```powershell
.\SekaiDesk.exe --instance dev
```

Runtime logs are written to `%LOCALAPPDATA%\SekaiDesk\startup.log`, and user settings live in `%APPDATA%\SekaiDesk\sekaidesk.json`.

## Pull Requests

- Keep PRs focused on a single fix or feature.
- Avoid adding external/proprietary assets or hardcoded local filesystem paths.
- Remember that SekaiDesk is licensed under **GNU GPL v3.0** — submitted contributions are licensed under GPL-3.0 as well.
