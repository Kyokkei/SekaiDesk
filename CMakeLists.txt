cmake_minimum_required(VERSION 3.21)
project(SekaiDesk VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Build on Windows (MinGW-w64 / MSVC) or cross-built on Colab.
# Qt 6.8+ recommended. Qt modules used: Core, Gui, Qml, Quick, Network.
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick Network)

qt_add_executable(SekaiDesk WIN32
    src/main.cpp
    src/compat/QsCore.h        src/compat/QsCore.cpp
    src/compat/QsWindow.h      src/compat/QsWindow.cpp
    src/compat/QsIo.h          src/compat/QsIo.cpp
    src/core/SettingsStore.h   src/core/SettingsStore.cpp
    src/services/WinIconProvider.h src/services/WinIconProvider.cpp
    src/services/AppLauncher.h     src/services/AppLauncher.cpp
    src/services/WindowTracker.h   src/services/WindowTracker.cpp
    src/services/DwmThumbnailItem.h src/services/DwmThumbnailItem.cpp
    src/services/TrashService.h    src/services/TrashService.cpp
    src/services/MediaService.h    src/services/MediaService.cpp
    src/services/AudioService.h    src/services/AudioService.cpp
    src/services/SystemControlService.h src/services/SystemControlService.cpp
    src/services/TrayService.h     src/services/TrayService.cpp
    src/services/ClipboardService.h src/services/ClipboardService.cpp
    src/services/DeskExtrasService.h src/services/DeskExtrasService.cpp
    src/services/NotificationService.h src/services/NotificationService.cpp
    src/services/VisualizerService.h src/services/VisualizerService.cpp
    src/services/WallpaperService.h src/services/WallpaperService.cpp
    src/SekaiDesk.rc
)

target_include_directories(SekaiDesk PRIVATE src)

# Smoke-test shell (Phase 0). Later phases swap this for the full SekaiPop shell.
qt_add_resources(SekaiDesk "qml"
    PREFIX "/"
    FILES
        qml/Shell.qml
        qml/ThemeHub.qml
        qml/ScreenRound.qml
        qml/SettingsModal.qml
        qml/PowerTools.qml
        qml/DesktopWidgets.qml
        qml/VisualizerOverlay.qml
        qml/SekaiOsd.qml
        qml/WallpaperSelector.qml
        qml/icons/alt-arrow-down-dark.svg
        qml/icons/alt-arrow-down-light.svg
        qml/icons/alt-arrow-up-dark.svg
        qml/icons/alt-arrow-up-light.svg
        qml/icons/arrow-down-dark.svg
        qml/icons/arrow-up-dark.svg
        qml/icons/bt-dark.svg
        qml/icons/bt-light.svg
        qml/icons/calendar-light.svg
        qml/icons/check-circle-dark.svg
        qml/icons/checklist-dark.svg
        qml/icons/clipboard-text-dark.svg
        qml/icons/clipboard-text-light.svg
        qml/icons/clock-circle-dark.svg
        qml/icons/clock-circle-light.svg
        qml/icons/close-circle-dark.svg
        qml/icons/cloud-dark.svg
        qml/icons/cloud-rain-dark.svg
        qml/icons/cloud-snowfall-dark.svg
        qml/icons/cloud-storm-dark.svg
        qml/icons/cloud-sun-dark.svg
        qml/icons/cloudy-moon-dark.svg
        qml/icons/copy-dark.svg
        qml/icons/fog-dark.svg
        qml/icons/folder-with-files-dark.svg
        qml/icons/folder-with-files-light.svg
        qml/icons/handsig-yozora.png
        qml/icons/headphones-round-dark.svg
        qml/icons/magnifer-dark.svg
        qml/icons/magnifer-light.svg
        qml/icons/map-point-teal.svg
        qml/icons/moon-dark.svg
        qml/icons/music-note-dark.svg
        qml/icons/music-note-teal.svg
        qml/icons/network-dark.svg
        qml/icons/network-light.svg
        qml/icons/notes-dark.svg
        qml/icons/palette-dark.svg
        qml/icons/palette-light.svg
        qml/icons/pause-dark.svg
        qml/icons/pin-dark.svg
        qml/icons/play-dark.svg
        qml/icons/refresh-light.svg
        qml/icons/settings-dark.svg
        qml/icons/settings-light.svg
        qml/icons/skip-next-dark.svg
        qml/icons/skip-previous-dark.svg
        qml/icons/sun-dark.svg
        qml/icons/trash-bin-trash-dark.svg
        qml/icons/trash-bin-trash-red.svg
        qml/icons/user-rounded-dark.svg
        qml/icons/volume-cross-dark.svg
        qml/icons/volume-cross-light.svg
        qml/icons/volume-loud-dark.svg
        qml/icons/volume-loud-light.svg
        qml/icons/waterdrop-dark.svg
        qml/icons/wifi-dark.svg
        qml/icons/wifi-light.svg
        qml/icons/wind-dark.svg
)

target_link_libraries(SekaiDesk PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Network
)

if(WIN32)
    target_link_libraries(SekaiDesk PRIVATE
        dwmapi user32 shell32 ole32 oleaut32 ws2_32 winhttp iphlpapi
    )
endif()

# ---------------------------------------------------------------------------
# qs.* import alias: SekaiPop QML does `import qs.services` / `qs.modules.*`.
# Quickshell resolves "qs." to the shell root; we emulate it by exposing the
# shell tree as <build>/qml/qs and adding <build>/qml as an import path in
# main.cpp. A NTFS junction is used when possible (fast, stays in sync);
# otherwise a full copy is made (also what the Colab zip package ships).
# ---------------------------------------------------------------------------
set(SEKAIDESK_SHELL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/SekaiPop/sekaipop")
file(CREATE_LINK "${SEKAIDESK_SHELL_DIR}" "${CMAKE_BINARY_DIR}/qml/qs"
     SYMBOLIC RESULT _qs_link_result)
if(NOT _qs_link_result EQUAL 0)
    message(STATUS "SekaiDesk: junction failed (${_qs_link_result}), copying shell tree")
    file(REMOVE_RECURSE "${CMAKE_BINARY_DIR}/qml/qs" "${CMAKE_BINARY_DIR}/qml/qs_tmp")
    file(COPY "${SEKAIDESK_SHELL_DIR}" DESTINATION "${CMAKE_BINARY_DIR}/qml/qs_tmp")
    file(RENAME "${CMAKE_BINARY_DIR}/qml/qs_tmp/sekaipop" "${CMAKE_BINARY_DIR}/qml/qs")
    file(REMOVE_RECURSE "${CMAKE_BINARY_DIR}/qml/qs_tmp")
endif()

install(TARGETS SekaiDesk RUNTIME DESTINATION .)
