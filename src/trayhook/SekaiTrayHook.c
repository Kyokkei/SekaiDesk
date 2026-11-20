#include "TrayHookProtocol.h"

#define WM_SEKAIDESK_UNHOOK (WM_APP + 1)
#define MAX_ICON_DIM        256U

#ifndef NIF_ICON
#define NIF_ICON 0x00000002U
#endif

_Static_assert(sizeof(SekaiPipeHeader) == 4, "SekaiPipeHeader size mismatch");
_Static_assert(sizeof(SekaiPipeCopyDataMsg) == 28, "SekaiPipeCopyDataMsg size mismatch");
_Static_assert(sizeof(SekaiNotifyIconData32) == 956, "SekaiNotifyIconData32 size mismatch");
_Static_assert(sizeof(SekaiShellTrayData) == 964, "SekaiShellTrayData size mismatch");

static volatile PVOID g_OldWndProc = NULL;
static HWND g_hTrayWnd = NULL;
static HANDLE g_hPipe = INVALID_HANDLE_VALUE;
static HMODULE g_hModule = NULL;
static CRITICAL_SECTION g_PipeCS;
static volatile LONG g_Initialized = 0;
static volatile LONG g_Detaching = 0;
static volatile LONG g_SafeToUnload = 0;
static HANDLE g_hUnhookDoneEvent = NULL;

__declspec(dllexport)
LRESULT CALLBACK GetMsgProc(int nCode, WPARAM wParam, LPARAM lParam)
{
    return CallNextHookEx(NULL, nCode, wParam, lParam);
}

static BOOL IsExplorer(void)
{
    WCHAR path[MAX_PATH];
    DWORD len = GetModuleFileNameW(NULL, path, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) {
        return FALSE;
    }

    WCHAR *lastSlash = NULL;
    for (WCHAR *p = path; *p != L'\0'; ++p) {
        if (*p == L'\\' || *p == L'/') {
            lastSlash = p;
        }
    }
    const WCHAR *base = lastSlash ? (lastSlash + 1) : path;
    return lstrcmpiW(base, L"explorer.exe") == 0;
}

static HWND FindRealSystray(void)
{
    const DWORD selfPid = GetCurrentProcessId();
    for (int tries = 0; tries < 40; ++tries) {
        if (InterlockedCompareExchange(&g_Detaching, 0, 0) != 0) {
            return NULL;
        }
        HWND candidate = NULL;
        while ((candidate = FindWindowExW(NULL, candidate, L"Shell_TrayWnd", NULL)) != NULL) {
            DWORD pid = 0;
            GetWindowThreadProcessId(candidate, &pid);
            if (pid == selfPid) {
                return candidate;
            }
        }
        Sleep(50);
    }
    return NULL;
}

static BOOL ExtractIconRGBA(HICON hIcon, BYTE **outRGBA, DWORD *outSize, DWORD *outW, DWORD *outH)
{
    if (!hIcon || !outRGBA || !outSize || !outW || !outH) {
        return FALSE;
    }
    *outRGBA = NULL;
    *outSize = 0;
    *outW = 0;
    *outH = 0;

    ICONINFO ii;
    ZeroMemory(&ii, sizeof(ii));
    if (!GetIconInfo(hIcon, &ii)) {
        return FALSE;
    }

    if (!ii.hbmColor) {
        if (ii.hbmMask) {
            DeleteObject(ii.hbmMask);
        }
        return FALSE;
    }

    BITMAP bm;
    ZeroMemory(&bm, sizeof(bm));
    if (GetObjectW(ii.hbmColor, sizeof(bm), &bm) == 0) {
        if (ii.hbmMask) {
            DeleteObject(ii.hbmMask);
        }
        DeleteObject(ii.hbmColor);
        return FALSE;
    }

    LONG rawH = bm.bmHeight < 0 ? -bm.bmHeight : bm.bmHeight;
    if (bm.bmWidth <= 0 || rawH <= 0 ||
        (DWORD)bm.bmWidth > MAX_ICON_DIM || (DWORD)rawH > MAX_ICON_DIM) {
        if (ii.hbmMask) {
            DeleteObject(ii.hbmMask);
        }
        DeleteObject(ii.hbmColor);
        return FALSE;
    }

    DWORD w = (DWORD)bm.bmWidth;
    DWORD h = (DWORD)rawH;
    DWORD pixelCount = w * h;
    DWORD dataSize = pixelCount * 4U;

    BYTE *rgba = (BYTE *)HeapAlloc(GetProcessHeap(), 0, dataSize);
    if (!rgba) {
        if (ii.hbmMask) {
            DeleteObject(ii.hbmMask);
        }
        DeleteObject(ii.hbmColor);
        return FALSE;
    }

    BITMAPINFOHEADER bi;
    ZeroMemory(&bi, sizeof(bi));
    bi.biSize = sizeof(bi);
    bi.biWidth = (LONG)w;
    bi.biHeight = -(LONG)h;
    bi.biPlanes = 1;
    bi.biBitCount = 32;
    bi.biCompression = BI_RGB;

    HDC hdc = CreateCompatibleDC(NULL);
    if (!hdc) {
        HeapFree(GetProcessHeap(), 0, rgba);
        if (ii.hbmMask) {
            DeleteObject(ii.hbmMask);
        }
        DeleteObject(ii.hbmColor);
        return FALSE;
    }

    BOOL ok = (GetDIBits(hdc, ii.hbmColor, 0, h, rgba, (BITMAPINFO *)&bi, DIB_RGB_COLORS) == (int)h);

    BOOL isMaskBased = TRUE;
    if (ok) {
        for (DWORD i = 0; i < pixelCount; ++i) {
            if (rgba[i * 4U + 3U] != 0) {
                isMaskBased = FALSE;
                break;
            }
        }
    }

    BYTE *maskBytes = NULL;
    BOOL maskOk = FALSE;
    if (ok && isMaskBased && ii.hbmMask) {
        maskBytes = (BYTE *)HeapAlloc(GetProcessHeap(), 0, dataSize);
        if (maskBytes) {
            maskOk = (GetDIBits(hdc, ii.hbmMask, 0, h, maskBytes, (BITMAPINFO *)&bi, DIB_RGB_COLORS) == (int)h);
        }
    }

    DeleteDC(hdc);

    if (ok) {
        for (DWORD i = 0; i < pixelCount; ++i) {
            BYTE b = rgba[i * 4U + 0U];
            BYTE g = rgba[i * 4U + 1U];
            BYTE r = rgba[i * 4U + 2U];
            BYTE a = rgba[i * 4U + 3U];
            if (isMaskBased) {
                if (maskOk && maskBytes) {
                    a = (maskBytes[i * 4U] == 255) ? 0 : 255;
                } else {
                    a = 255;
                }
            }
            rgba[i * 4U + 0U] = r;
            rgba[i * 4U + 1U] = g;
            rgba[i * 4U + 2U] = b;
            rgba[i * 4U + 3U] = a;
        }
        *outRGBA = rgba;
        *outSize = dataSize;
        *outW = w;
        *outH = h;
    } else {
        HeapFree(GetProcessHeap(), 0, rgba);
    }

    if (maskBytes) {
        HeapFree(GetProcessHeap(), 0, maskBytes);
    }
    if (ii.hbmMask) {
        DeleteObject(ii.hbmMask);
    }
    DeleteObject(ii.hbmColor);
    return ok;
}

static void InternalWriteToPipe(const void *buffer, DWORD totalSize)
{
    if (!buffer || totalSize == 0) {
        return;
    }

    EnterCriticalSection(&g_PipeCS);
    if (g_hPipe != INVALID_HANDLE_VALUE) {
        OVERLAPPED ov;
        ZeroMemory(&ov, sizeof(ov));
        ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
        if (ov.hEvent) {
            DWORD written = 0;
            if (!WriteFile(g_hPipe, buffer, totalSize, &written, &ov)) {
                DWORD err = GetLastError();
                if (err == ERROR_IO_PENDING) {
                    if (WaitForSingleObject(ov.hEvent, 500) != WAIT_OBJECT_0) {
                        CancelIo(g_hPipe);
                        DWORD unused = 0;
                        GetOverlappedResult(g_hPipe, &ov, &unused, TRUE);
                        CloseHandle(g_hPipe);
                        g_hPipe = INVALID_HANDLE_VALUE;
                    }
                } else {
                    CloseHandle(g_hPipe);
                    g_hPipe = INVALID_HANDLE_VALUE;
                }
            }
            CloseHandle(ov.hEvent);
        }
    }
    LeaveCriticalSection(&g_PipeCS);
}

static void SendReadyToPipe(void)
{
    SekaiPipeHeader hdr;
    hdr.type = SEKAI_TRAY_MSG_READY;
    InternalWriteToPipe(&hdr, (DWORD)sizeof(hdr));
}

static void SendCopyDataToPipe(PCOPYDATASTRUCT pcds)
{
    if (!pcds || !pcds->lpData || pcds->cbData < 32U || pcds->cbData > 65536U) {
        return;
    }

    SekaiShellTrayData st;
    ZeroMemory(&st, sizeof(st));
    DWORD inspectLen = pcds->cbData < (DWORD)sizeof(st) ? pcds->cbData : (DWORD)sizeof(st);
    CopyMemory(&st, pcds->lpData, inspectLen);

    BYTE *iconRGBA = NULL;
    DWORD iconSize = 0;
    DWORD iconW = 0;
    DWORD iconH = 0;

    if ((st.nid.uFlags & NIF_ICON) && st.nid.hIcon != 0) {
        HICON rawIcon = (HICON)(INT_PTR)(int32_t)st.nid.hIcon;
        HICON iconCopy = CopyIcon(rawIcon);
        if (iconCopy) {
            ExtractIconRGBA(iconCopy, &iconRGBA, &iconSize, &iconW, &iconH);
            DestroyIcon(iconCopy);
        }
    }

    SekaiPipeCopyDataMsg msg;
    ZeroMemory(&msg, sizeof(msg));
    msg.header.type = SEKAI_TRAY_MSG_COPYDATA;
    msg.dwData = (uint64_t)pcds->dwData;
    msg.cbData = (uint32_t)pcds->cbData;
    msg.iconWidth = (uint32_t)iconW;
    msg.iconHeight = (uint32_t)iconH;
    msg.iconDataSize = (uint32_t)iconSize;

    DWORD totalSize = (DWORD)sizeof(msg) + pcds->cbData + iconSize;
    BYTE *packet = (BYTE *)HeapAlloc(GetProcessHeap(), 0, totalSize);
    if (packet) {
        BYTE *cursor = packet;
        CopyMemory(cursor, &msg, sizeof(msg));
        cursor += sizeof(msg);
        CopyMemory(cursor, pcds->lpData, pcds->cbData);
        cursor += pcds->cbData;
        if (iconSize > 0 && iconRGBA) {
            CopyMemory(cursor, iconRGBA, iconSize);
        }
        InternalWriteToPipe(packet, totalSize);
        HeapFree(GetProcessHeap(), 0, packet);
    }

    if (iconRGBA) {
        HeapFree(GetProcessHeap(), 0, iconRGBA);
    }
}

static LRESULT CALLBACK ManualSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
{
    WNDPROC oldProc = (WNDPROC)InterlockedCompareExchangePointer(&g_OldWndProc, NULL, NULL);

    if (uMsg == WM_SEKAIDESK_UNHOOK) {
        if (oldProc && (WNDPROC)GetWindowLongPtrW(hWnd, GWLP_WNDPROC) == ManualSubclassProc) {
            SetWindowLongPtrW(hWnd, GWLP_WNDPROC, (LONG_PTR)oldProc);
            InterlockedExchangePointer(&g_OldWndProc, NULL);
            InterlockedExchange(&g_SafeToUnload, 1);
        } else if (!oldProc) {
            InterlockedExchange(&g_SafeToUnload, 1);
        }
        if (g_hUnhookDoneEvent) {
            SetEvent(g_hUnhookDoneEvent);
        }
        return 0;
    }

    if (uMsg == WM_NCDESTROY) {
        if (oldProc && (WNDPROC)GetWindowLongPtrW(hWnd, GWLP_WNDPROC) == ManualSubclassProc) {
            SetWindowLongPtrW(hWnd, GWLP_WNDPROC, (LONG_PTR)oldProc);
            InterlockedExchangePointer(&g_OldWndProc, NULL);
            InterlockedExchange(&g_SafeToUnload, 1);
        }
        EnterCriticalSection(&g_PipeCS);
        if (g_hPipe != INVALID_HANDLE_VALUE) {
            CloseHandle(g_hPipe);
            g_hPipe = INVALID_HANDLE_VALUE;
        }
        LeaveCriticalSection(&g_PipeCS);
    }

    if (InterlockedCompareExchange(&g_Detaching, 0, 0) == 0 && uMsg == WM_COPYDATA) {
        PCOPYDATASTRUCT pcds = (PCOPYDATASTRUCT)lParam;
        if (pcds && pcds->dwData == 1 && pcds->lpData && pcds->cbData >= 32U && pcds->cbData <= 65536U) {
            SendCopyDataToPipe(pcds);
        }
    }

    if (oldProc && oldProc != ManualSubclassProc) {
        return CallWindowProcW(oldProc, hWnd, uMsg, wParam, lParam);
    }
    return DefWindowProcW(hWnd, uMsg, wParam, lParam);
}

static DWORD WINAPI InitAndWatchdogThread(LPVOID lpParam)
{
    (void)lpParam;

    WCHAR dllPath[MAX_PATH];
    HMODULE pinned = NULL;
    DWORD pathLen = GetModuleFileNameW(g_hModule, dllPath, MAX_PATH);
    if (pathLen > 0 && pathLen < MAX_PATH) {
        pinned = LoadLibraryW(dllPath);
    }

    g_hUnhookDoneEvent = CreateEventW(NULL, TRUE, FALSE, NULL);

    HANDLE hPipe = INVALID_HANDLE_VALUE;
    for (int attempt = 0; attempt < 40 && InterlockedCompareExchange(&g_Detaching, 0, 0) == 0; ++attempt) {
        hPipe = CreateFileW(SEKAI_TRAY_PIPE_NAME, GENERIC_WRITE, 0, NULL,
                            OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL);
        if (hPipe != INVALID_HANDLE_VALUE) {
            break;
        }
        if (GetLastError() == ERROR_PIPE_BUSY) {
            WaitNamedPipeW(SEKAI_TRAY_PIPE_NAME, 50);
        } else {
            Sleep(50);
        }
    }

    BOOL subclassed = FALSE;
    if (hPipe != INVALID_HANDLE_VALUE) {
        EnterCriticalSection(&g_PipeCS);
        g_hPipe = hPipe;
        LeaveCriticalSection(&g_PipeCS);

        HWND hTray = FindRealSystray();
        if (hTray) {
            WNDPROC expected = (WNDPROC)GetWindowLongPtrW(hTray, GWLP_WNDPROC);
            if (expected && expected != ManualSubclassProc) {
                InterlockedExchangePointer(&g_OldWndProc, (PVOID)expected);
                WNDPROC actual = (WNDPROC)SetWindowLongPtrW(hTray, GWLP_WNDPROC, (LONG_PTR)ManualSubclassProc);
                if (actual) {
                    if (actual != ManualSubclassProc && actual != expected) {
                        InterlockedExchangePointer(&g_OldWndProc, (PVOID)actual);
                    }
                    g_hTrayWnd = hTray;
                    subclassed = TRUE;
                    SendReadyToPipe();
                } else {
                    InterlockedExchangePointer(&g_OldWndProc, NULL);
                }
            }
        }
    }

    if (subclassed) {
        HANDLE hMutex = OpenMutexW(SYNCHRONIZE | MUTEX_MODIFY_STATE, FALSE, SEKAI_TRAY_WATCHDOG_MUTEX);
        if (hMutex) {
            DWORD waitRes = WaitForSingleObject(hMutex, INFINITE);
            if (waitRes == WAIT_OBJECT_0 || waitRes == WAIT_ABANDONED) {
                ReleaseMutex(hMutex);
            }
            CloseHandle(hMutex);
        }

        InterlockedExchange(&g_Detaching, 1);

        if (g_hTrayWnd && IsWindow(g_hTrayWnd) &&
            InterlockedCompareExchangePointer(&g_OldWndProc, NULL, NULL) != NULL) {
            PostMessageW(g_hTrayWnd, WM_SEKAIDESK_UNHOOK, 0, 0);
            if (g_hUnhookDoneEvent) {
                WaitForSingleObject(g_hUnhookDoneEvent, 5000);
            }
        } else {
            InterlockedExchange(&g_SafeToUnload, 1);
        }
    } else {
        InterlockedExchange(&g_Detaching, 1);
        InterlockedExchange(&g_SafeToUnload, 1);
    }

    EnterCriticalSection(&g_PipeCS);
    if (g_hPipe != INVALID_HANDLE_VALUE) {
        CloseHandle(g_hPipe);
        g_hPipe = INVALID_HANDLE_VALUE;
    }
    LeaveCriticalSection(&g_PipeCS);

    if (g_hUnhookDoneEvent) {
        CloseHandle(g_hUnhookDoneEvent);
        g_hUnhookDoneEvent = NULL;
    }

    if (pinned && InterlockedCompareExchange(&g_SafeToUnload, 0, 0) != 0) {
        FreeLibraryAndExitThread(g_hModule, 0);
    }
    return 0;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved)
{
    if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
        if (!IsExplorer()) {
            return TRUE;
        }
        if (InterlockedCompareExchange(&g_Initialized, 1, 0) != 0) {
            return TRUE;
        }
        InitializeCriticalSection(&g_PipeCS);
        DisableThreadLibraryCalls(hModule);
        g_hModule = hModule;
        HANDLE hThread = CreateThread(NULL, 0, InitAndWatchdogThread, NULL, 0, NULL);
        if (hThread) {
            CloseHandle(hThread);
        } else {
            DeleteCriticalSection(&g_PipeCS);
            InterlockedExchange(&g_Initialized, 0);
        }
    } else if (ul_reason_for_call == DLL_PROCESS_DETACH) {
        if (lpReserved == NULL && InterlockedCompareExchange(&g_Initialized, 0, 1) == 1) {
            DeleteCriticalSection(&g_PipeCS);
        }
    }
    return TRUE;
}
