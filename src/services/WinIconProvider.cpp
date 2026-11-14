#include "WinIconProvider.h"

#include <QDir>
#include <QFileInfo>
#include <QPainter>
#include <QUrl>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <commoncontrols.h>
#include <objbase.h>
#endif

WinIconProvider::WinIconProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

#ifdef Q_OS_WIN
static QString stripWinIconPrefix(const QString& decoded)
{
    QString s = decoded.trimmed();
    if (s.startsWith(QStringLiteral("exe/"), Qt::CaseInsensitive)
        || s.startsWith(QStringLiteral("exe\\"), Qt::CaseInsensitive)
        || s.startsWith(QStringLiteral("lnk/"), Qt::CaseInsensitive)
        || s.startsWith(QStringLiteral("lnk\\"), Qt::CaseInsensitive)) {
        s = s.mid(4);
    }
    if (s.startsWith(QStringLiteral("file:///"), Qt::CaseInsensitive)) {
        const QString local = QUrl(s).toLocalFile();
        if (!local.isEmpty())
            s = local;
    }
    if (s.size() >= 2 && s.startsWith(QLatin1Char('"')) && s.endsWith(QLatin1Char('"')))
        s = s.mid(1, s.size() - 2);
    return s.trimmed();
}

static QString expandEnvVars(const QString& raw)
{
    if (raw.isEmpty())
        return {};
    wchar_t expanded[MAX_PATH * 2] = {};
    const DWORD n = ExpandEnvironmentStringsW(
        reinterpret_cast<const wchar_t*>(raw.utf16()),
        expanded, MAX_PATH * 2);
    if (n > 0 && n < MAX_PATH * 2)
        return QString::fromWCharArray(expanded);
    return raw;
}

static QString resolveExecutablePath(const QString& rawTarget)
{
    QString target = expandEnvVars(rawTarget.trimmed());
    if (target.isEmpty())
        return {};

    if (!target.startsWith(QStringLiteral("ms-settings:"), Qt::CaseInsensitive)
        && !target.startsWith(QStringLiteral("shell:"), Qt::CaseInsensitive)) {
        target = QDir::toNativeSeparators(target);
    }

    // If it's a bare executable name (e.g. "calc.exe", "wt.exe"), locate it via PATH.
    if (!target.contains(QLatin1Char('\\')) && !target.contains(QLatin1Char('/'))
        && !target.contains(QLatin1Char(':'))) {
        wchar_t found[MAX_PATH] = {};
        if (SearchPathW(nullptr,
                        reinterpret_cast<const wchar_t*>(target.utf16()),
                        nullptr, MAX_PATH, found, nullptr) > 0) {
            return QString::fromWCharArray(found);
        }
    }
    return target;
}

static HICON iconFromImageListIndex(int sysIconIndex)
{
    if (sysIconIndex < 0)
        return nullptr;
    static const IID kIID_IImageList = {
        0x46EB5926, 0x582E, 0x4017, {0x9F, 0xDF, 0xE8, 0x99, 0x8D, 0xAA, 0x09, 0x50}
    };
    for (int shil : { SHIL_JUMBO, SHIL_EXTRALARGE }) {
        IImageList* imgList = nullptr;
        if (SUCCEEDED(SHGetImageList(shil, kIID_IImageList,
                                     reinterpret_cast<void**>(&imgList))) && imgList) {
            HICON hIcon = nullptr;
            const HRESULT hr = imgList->GetIcon(sysIconIndex, ILD_TRANSPARENT, &hIcon);
            imgList->Release();
            if (SUCCEEDED(hr) && hIcon)
                return hIcon;
        }
    }
    return nullptr;
}

static HICON extractViaShGetFileInfo(const QString& nativePath, UINT extraFlags = 0, DWORD fileAttrs = 0)
{
    if (nativePath.isEmpty())
        return nullptr;

    SHFILEINFOW sfi = {};
    const DWORD_PTR ok = SHGetFileInfoW(
        reinterpret_cast<const wchar_t*>(nativePath.utf16()),
        fileAttrs, &sfi, sizeof(sfi),
        SHGFI_SYSICONINDEX | extraFlags);

    if (ok) {
        if (HICON hIcon = iconFromImageListIndex(sfi.iIcon))
            return hIcon;
    }

    ZeroMemory(&sfi, sizeof(sfi));
    if (SHGetFileInfoW(reinterpret_cast<const wchar_t*>(nativePath.utf16()),
                       fileAttrs, &sfi, sizeof(sfi),
                       SHGFI_ICON | SHGFI_LARGEICON | extraFlags) && sfi.hIcon) {
        return sfi.hIcon;
    }
    return nullptr;
}

static HICON extractViaShellLink(const QString& lnkPath)
{
    static const CLSID kCLSID_ShellLink = {
        0x00021401, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}
    };
    static const IID kIID_IShellLinkW = {
        0x000214F9, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}
    };
    static const IID kIID_IPersistFile = {
        0x0000010B, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}
    };

    IShellLinkW* psl = nullptr;
    if (FAILED(CoCreateInstance(kCLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                kIID_IShellLinkW, reinterpret_cast<void**>(&psl))) || !psl) {
        return nullptr;
    }

    HICON result = nullptr;
    IPersistFile* ppf = nullptr;
    if (SUCCEEDED(psl->QueryInterface(kIID_IPersistFile, reinterpret_cast<void**>(&ppf))) && ppf) {
        if (SUCCEEDED(ppf->Load(reinterpret_cast<const wchar_t*>(lnkPath.utf16()), STGM_READ))) {
            wchar_t iconLoc[MAX_PATH] = {};
            int iconIdx = 0;
            if (SUCCEEDED(psl->GetIconLocation(iconLoc, MAX_PATH, &iconIdx)) && iconLoc[0] != L'\0') {
                const QString resolvedIconLoc = resolveExecutablePath(QString::fromWCharArray(iconLoc));
                if (!resolvedIconLoc.isEmpty()) {
                    HICON hLarge = nullptr;
                    if (ExtractIconExW(reinterpret_cast<const wchar_t*>(resolvedIconLoc.utf16()),
                                       iconIdx, &hLarge, nullptr, 1) > 0 && hLarge) {
                        result = hLarge;
                    } else {
                        result = extractViaShGetFileInfo(resolvedIconLoc);
                    }
                }
            }

            if (!result) {
                wchar_t targetBuf[MAX_PATH] = {};
                if (SUCCEEDED(psl->GetPath(targetBuf, MAX_PATH, nullptr, 0)) && targetBuf[0] != L'\0') {
                    const QString targetExe = resolveExecutablePath(QString::fromWCharArray(targetBuf));
                    result = extractViaShGetFileInfo(targetExe);
                }
            }
            if (!result) {
                wchar_t rawTargetBuf[MAX_PATH] = {};
                if (SUCCEEDED(psl->GetPath(rawTargetBuf, MAX_PATH, nullptr, SLGP_RAWPATH)) && rawTargetBuf[0] != L'\0') {
                    const QString targetExe = resolveExecutablePath(QString::fromWCharArray(rawTargetBuf));
                    result = extractViaShGetFileInfo(targetExe);
                }
            }
        }
        ppf->Release();
    }
    psl->Release();
    return result;
}

static HICON extractBestIcon(const QString& target)
{
    const QString resolved = resolveExecutablePath(target);
    if (resolved.isEmpty())
        return nullptr;

    // Special URI schemes like ms-settings: -> use Windows control/settings icon from shell32/imageres.
    if (resolved.startsWith(QStringLiteral("ms-settings:"), Qt::CaseInsensitive)) {
        HICON hIcon = nullptr;
        const wchar_t* sysSettings = L"C:\\Windows\\ImmersiveControlPanel\\SystemSettings.exe";
        if (GetFileAttributesW(sysSettings) != INVALID_FILE_ATTRIBUTES) {
            if (HICON hi = extractViaShGetFileInfo(QString::fromWCharArray(sysSettings)))
                return hi;
        }
        ExtractIconExW(L"shell32.dll", 316, &hIcon, nullptr, 1);
        if (hIcon)
            return hIcon;
    }

    // UWP / shell:AppsFolder targets via PIDL
    if (resolved.startsWith(QStringLiteral("shell:"), Qt::CaseInsensitive)) {
        PIDLIST_ABSOLUTE pidl = nullptr;
        if (SUCCEEDED(SHParseDisplayName(reinterpret_cast<const wchar_t*>(resolved.utf16()),
                                         nullptr, &pidl, 0, nullptr)) && pidl) {
            SHFILEINFOW sfi = {};
            HICON hIcon = nullptr;
            if (SHGetFileInfoW(reinterpret_cast<LPCWSTR>(pidl), 0, &sfi, sizeof(sfi),
                               SHGFI_PIDL | SHGFI_SYSICONINDEX)) {
                hIcon = iconFromImageListIndex(sfi.iIcon);
            }
            if (!hIcon) {
                ZeroMemory(&sfi, sizeof(sfi));
                if (SHGetFileInfoW(reinterpret_cast<LPCWSTR>(pidl), 0, &sfi, sizeof(sfi),
                                   SHGFI_PIDL | SHGFI_ICON | SHGFI_LARGEICON)) {
                    hIcon = sfi.hIcon;
                }
            }
            CoTaskMemFree(pidl);
            if (hIcon)
                return hIcon;
        }
    }

    if (HICON hIcon = extractViaShGetFileInfo(resolved))
        return hIcon;

    if (resolved.endsWith(QStringLiteral(".lnk"), Qt::CaseInsensitive)) {
        if (HICON hIcon = extractViaShellLink(resolved))
            return hIcon;
    }

    if (resolved.endsWith(QStringLiteral(".exe"), Qt::CaseInsensitive)
        || resolved.endsWith(QStringLiteral(".lnk"), Qt::CaseInsensitive)
        || resolved.endsWith(QStringLiteral(".msc"), Qt::CaseInsensitive)) {
        if (HICON hIcon = extractViaShGetFileInfo(resolved, SHGFI_USEFILEATTRIBUTES, FILE_ATTRIBUTE_NORMAL))
            return hIcon;
    }

    return nullptr;
}
#endif

QImage WinIconProvider::requestImage(const QString& id, QSize* size,
                                     const QSize& requestedSize)
{
    const QString decoded = QUrl::fromPercentEncoding(id.toUtf8());
    QImage img;

#ifdef Q_OS_WIN
    const QString cleanPath = stripWinIconPrefix(decoded);
    const HRESULT hrCom = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool didCoInit = SUCCEEDED(hrCom);
    if (HICON hIcon = extractBestIcon(cleanPath)) {
        img = QImage::fromHICON(hIcon);
        DestroyIcon(hIcon);
    }
    if (didCoInit)
        CoUninitialize();
#else
    const QString cleanPath = decoded;
#endif

    if (img.isNull()) {
        // Clean pastel placeholder badge if no icon could be extracted.
        const int dim = requestedSize.isValid() ? qMax(32, requestedSize.width()) : 64;
        img = QImage(dim, dim, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing, true);
        p.setBrush(QColor(0x64, 0x74, 0x8B));
        p.setPen(Qt::NoPen);
        p.drawRoundedRect(4, 4, dim - 8, dim - 8, 14, 14);
        p.setPen(Qt::white);
        QFont f = p.font();
        f.setPixelSize(dim / 2);
        f.setBold(true);
        p.setFont(f);
        QString base = QFileInfo(QDir::fromNativeSeparators(cleanPath)).completeBaseName();
        if (base.isEmpty())
            base = cleanPath.section(QLatin1Char('\\'), -1);
        const QString letter = base.isEmpty() ? QStringLiteral("?") : base.left(1).toUpper();
        p.drawText(img.rect(), Qt::AlignCenter, letter);
    } else if (requestedSize.isValid() && requestedSize.width() > 0 && requestedSize.height() > 0) {
        img = img.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }

    if (size)
        *size = img.size();
    return img;
}
