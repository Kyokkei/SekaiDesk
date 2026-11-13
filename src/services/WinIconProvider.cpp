#include "WinIconProvider.h"

#include <QPainter>
#include <QUrl>

#ifdef Q_OS_WIN
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <commoncontrols.h>
#include <objbase.h>
#endif

WinIconProvider::WinIconProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

#ifdef Q_OS_WIN
static QString resolveExecutablePath(const QString& rawTarget)
{
    QString target = rawTarget.trimmed();
    if (target.isEmpty())
        return {};

    // Expand environment variables like %SystemRoot% if present.
    wchar_t expanded[MAX_PATH] = {};
    if (ExpandEnvironmentStringsW(reinterpret_cast<const wchar_t*>(target.utf16()),
                                  expanded, MAX_PATH) > 0) {
        target = QString::fromWCharArray(expanded);
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

static HICON extractBestIcon(const QString& target)
{
    const QString resolved = resolveExecutablePath(target);
    if (resolved.isEmpty())
        return nullptr;

    // Special URI schemes like ms-settings: -> use Windows control/settings icon from shell32/imageres.
    if (resolved.startsWith(QStringLiteral("ms-settings:"), Qt::CaseInsensitive)) {
        HICON hIcon = nullptr;
        // imageres.dll icon index 62 / shell32.dll fallback
        const wchar_t* sysSettings = L"C:\\Windows\\ImmersiveControlPanel\\SystemSettings.exe";
        if (GetFileAttributesW(sysSettings) != INVALID_FILE_ATTRIBUTES) {
            SHFILEINFOW sfi = {};
            if (SHGetFileInfoW(sysSettings, 0, &sfi, sizeof(sfi),
                               SHGFI_ICON | SHGFI_LARGEICON) && sfi.hIcon) {
                return sfi.hIcon;
            }
        }
        ExtractIconExW(L"shell32.dll", 316, &hIcon, nullptr, 1);
        if (hIcon)
            return hIcon;
    }

    // Try jumbo / extra-large system image list first for crisp 64px+ icons.
    SHFILEINFOW sfi = {};
    const DWORD_PTR ok = SHGetFileInfoW(
        reinterpret_cast<const wchar_t*>(resolved.utf16()),
        0, &sfi, sizeof(sfi),
        SHGFI_SYSICONINDEX);

    if (ok && sfi.iIcon >= 0) {
        static const IID kIID_IImageList = {
            0x46EB5926, 0x582E, 0x4017, {0x9F, 0xDF, 0xE8, 0x99, 0x8D, 0xAA, 0x09, 0x50}
        };
        IImageList* imgList = nullptr;
        // Try SHIL_JUMBO (256x256) then SHIL_EXTRALARGE (48x48)
        for (int shil : { SHIL_JUMBO, SHIL_EXTRALARGE }) {
            if (SUCCEEDED(SHGetImageList(shil, kIID_IImageList,
                                         reinterpret_cast<void**>(&imgList))) && imgList) {
                HICON hIcon = nullptr;
                const HRESULT hr = imgList->GetIcon(sfi.iIcon, ILD_TRANSPARENT, &hIcon);
                imgList->Release();
                if (SUCCEEDED(hr) && hIcon)
                    return hIcon;
            }
        }
    }

    // Fallback: standard SHGFI_ICON | SHGFI_LARGEICON
    ZeroMemory(&sfi, sizeof(sfi));
    if (SHGetFileInfoW(reinterpret_cast<const wchar_t*>(resolved.utf16()),
                       0, &sfi, sizeof(sfi),
                       SHGFI_ICON | SHGFI_LARGEICON) && sfi.hIcon) {
        return sfi.hIcon;
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
    if (HICON hIcon = extractBestIcon(decoded)) {
        img = QImage::fromHICON(hIcon);
        DestroyIcon(hIcon);
    }
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
        const QString letter = decoded.isEmpty()
            ? QStringLiteral("?")
            : decoded.section(QLatin1Char('\\'), -1).left(1).toUpper();
        p.drawText(img.rect(), Qt::AlignCenter, letter);
    } else if (requestedSize.isValid() && requestedSize.width() > 0 && requestedSize.height() > 0) {
        img = img.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }

    if (size)
        *size = img.size();
    return img;
}
