#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SEKAI_TRAY_PIPE_NAME        L"\\\\.\\pipe\\sekaidesk_tray_monitor"
#define SEKAI_TRAY_WATCHDOG_MUTEX   L"Local\\SekaiDeskTrayHookAlive"
#define SEKAI_TRAY_PIPE_BUFFER_SIZE (64U * 1024U)

#define SEKAI_TRAY_MSG_TEXT     1U
#define SEKAI_TRAY_MSG_COPYDATA 2U
#define SEKAI_TRAY_MSG_READY    3U

#pragma pack(push, 1)
typedef struct SekaiPipeHeader {
    uint32_t type;
} SekaiPipeHeader;

typedef struct SekaiPipeCopyDataMsg {
    SekaiPipeHeader header;
    uint64_t dwData;
    uint32_t cbData;
    uint32_t iconWidth;
    uint32_t iconHeight;
    uint32_t iconDataSize;
} SekaiPipeCopyDataMsg;

typedef struct SekaiNotifyIconData32 {
    uint32_t cbSize;
    uint32_t hWnd;
    uint32_t uID;
    uint32_t uFlags;
    uint32_t uCallbackMessage;
    uint32_t hIcon;
    WCHAR szTip[128];
    uint32_t dwState;
    uint32_t dwStateMask;
    WCHAR szInfo[256];
    uint32_t uVersion;
    WCHAR szInfoTitle[64];
    uint32_t dwInfoFlags;
    GUID guidItem;
    uint32_t hBalloonIcon;
} SekaiNotifyIconData32;

typedef struct SekaiShellTrayData {
    int32_t dwSignature;
    uint32_t dwMessage;
    SekaiNotifyIconData32 nid;
} SekaiShellTrayData;
#pragma pack(pop)

#ifdef __cplusplus
}
#endif
