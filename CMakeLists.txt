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
)

# Smoke-test shell (Phase 0). Later phases swap this for the full SekaiPop shell.
qt_add_resources(SekaiDesk "qml"
    PREFIX "/qml"
    FILES qml/Shell.qml
)

target_link_libraries(SekaiDesk PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Network
)

if(WIN32)
    target_link_libraries(SekaiDesk PRIVATE
        dwmapi user32 shell32 ole32 oleaut32 ws2_32
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
    file(COPY "${SEKAIDESK_SHELL_DIR}" DESTINATION "${CMAKE_BINARY_DIR}/qml/qs_tmp")
    file(RENAME "${CMAKE_BINARY_DIR}/qml/qs_tmp/sekaipop" "${CMAKE_BINARY_DIR}/qml/qs")
    file(REMOVE_RECURSE "${CMAKE_BINARY_DIR}/qml/qs_tmp")
endif()

install(TARGETS SekaiDesk RUNTIME DESTINATION .)
