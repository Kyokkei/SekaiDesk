#include "WinIconProvider.h"

#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QPainter>
#include <QRect>
#include <QUrl>

#include <cstdlib>

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

static QRect findContentBoundingBox(const QImage& argb)
{
    if (argb.isNull())
        return {};
    const int w = argb.width();
    const int h = argb.height();
    int minX = w;
    int minY = h;
    int maxX = -1;
    int maxY = -1;
    for (int y = 0; y < h; ++y) {
        const QRgb* row = reinterpret_cast<const QRgb*>(argb.constScanLine(y));
        for (int x = 0; x < w; ++x) {
            if (qAlpha(row[x]) > 12) {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
    }
    if (maxX < minX || maxY < minY)
        return {};
    return QRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

static QImage normalizeIconImage(const QImage& raw)
{
    if (raw.isNull())
        return {};
    const QImage argb = (raw.format() == QImage::Format_ARGB32)
        ? raw
        : raw.convertToFormat(QImage::Format_ARGB32);
    const QRect bbox = findContentBoundingBox(argb);
    if (bbox.isEmpty())
        return {};

    const int w = argb.width();
    const int h = argb.height();
    const int bw = bbox.width();
    const int bh = bbox.height();

    // Fix Windows SHIL_JUMBO top-left unscaled icon bug (tiny icon parked in top-left of 256x256 canvas)
    const bool stuckSmallOrOffset =
        (bw <= qRound(w * 0.60) && bh <= qRound(h * 0.60))
        || (bbox.right() < qRound(w * 0.65) && bbox.bottom() < qRound(h * 0.65)
            && (bw * bh) < (w * h) / 3);
    if (!stuckSmallOrOffset)
        return argb;

    const int maxDim = qMax(bw, bh);
    const int pad = qMax(2, maxDim / 14);
    const int side = maxDim + pad * 2;
    QImage squared(side, side, QImage::Format_ARGB32);
    squared.fill(Qt::transparent);
    QPainter p(&squared);
    p.setRenderHint(QPainter::SmoothPixmapTransform, true);
    const int dx = (side - bw) / 2;
    const int dy = (side - bh) / 2;
    p.drawImage(dx, dy, argb, bbox.x(), bbox.y(), bw, bh);
    p.end();
    return squared;
}

static QImage qimageFromHIconDestroy(HICON hIcon)
{
    if (!hIcon)
        return {};
    QImage img = QImage::fromHICON(hIcon);
    DestroyIcon(hIcon);
    if (img.isNull())
        return {};
    if (img.format() != QImage::Format_ARGB32)
        img = img.convertToFormat(QImage::Format_ARGB32);
    if (findContentBoundingBox(img).isEmpty())
        return {};
    return img;
}

static QImage qimageFromHBitmap(HBITMAP hBmp)
{
    if (!hBmp)
        return {};
    BITMAP bm{};
    if (!GetObjectW(hBmp, sizeof(bm), &bm) || bm.bmWidth <= 0 || bm.bmHeight == 0) {
        DeleteObject(hBmp);
        return {};
    }
    const int w = bm.bmWidth;
    const int h = std::abs(bm.bmHeight);
    BITMAPINFOHEADER bi{};
    bi.biSize = sizeof(bi);
    bi.biWidth = w;
    bi.biHeight = -h;
    bi.biPlanes = 1;
    bi.biBitCount = 32;
    bi.biCompression = BI_RGB;

    QImage raw(w, h, QImage::Format_ARGB32);
    raw.fill(0);
    HDC hdc = CreateCompatibleDC(nullptr);
    const int lines = GetDIBits(hdc, hBmp, 0, static_cast<UINT>(h),
                                raw.bits(), reinterpret_cast<BITMAPINFO*>(&bi),
                                DIB_RGB_COLORS);
    DeleteDC(hdc);
    DeleteObject(hBmp);
    if (lines == 0)
        return {};

    bool anyNonZeroAlpha = false;
    bool looksStraightAlpha = false;
    for (int y = 0; y < h; ++y) {
        const QRgb* row = reinterpret_cast<const QRgb*>(raw.constScanLine(y));
        for (int x = 0; x < w; ++x) {
            const int a = qAlpha(row[x]);
            if (a != 0) {
                anyNonZeroAlpha = true;
                if (qRed(row[x]) > a || qGreen(row[x]) > a || qBlue(row[x]) > a)
                    looksStraightAlpha = true;
            }
        }
    }
    if (!anyNonZeroAlpha) {
        for (int y = 0; y < h; ++y) {
            QRgb* row = reinterpret_cast<QRgb*>(raw.scanLine(y));
            for (int x = 0; x < w; ++x) {
                if ((row[x] & 0x00FFFFFFu) != 0)
                    row[x] |= 0xFF000000u;
            }
        }
        return raw;
    }
    if (looksStraightAlpha)
        return raw;
    QImage premul(raw.constBits(), w, h, raw.bytesPerLine(), QImage::Format_ARGB32_Premultiplied);
    return premul.convertToFormat(QImage::Format_ARGB32);
}

static QImage extractViaShellItemImageFactory(const QString& parsingName, int dim = 256)
{
    if (parsingName.isEmpty())
        return {};
    using FnSHCreateItemFromParsingName = HRESULT(WINAPI*)(PCWSTR, IBindCtx*, REFIID, void**);
    HMODULE shell32 = GetModuleHandleW(L"shell32.dll");
    if (!shell32)
        shell32 = LoadLibraryW(L"shell32.dll");
    auto fnCreateItem = shell32
        ? reinterpret_cast<FnSHCreateItemFromParsingName>(
              GetProcAddress(shell32, "SHCreateItemFromParsingName"))
        : nullptr;
    if (!fnCreateItem)
        return {};

    static constexpr IID kIID_IShellItemImageFactory = {
        0xBCC18B79, 0xBA16, 0x442F, {0x80, 0xC4, 0x8A, 0x59, 0xC3, 0x0C, 0x46, 0x3B}
    };
    IShellItemImageFactory* factory = nullptr;
    const HRESULT hr = fnCreateItem(
        reinterpret_cast<const wchar_t*>(parsingName.utf16()),
        nullptr, kIID_IShellItemImageFactory, reinterpret_cast<void**>(&factory));
    if (FAILED(hr) || !factory)
        return {};

    HBITMAP hBmp = nullptr;
    const SIZE sz{ dim, dim };
    QImage out;
    // SIIGBF_BIGGERSIZEOK (0x1) | SIIGBF_ICONONLY (0x4)
    if (SUCCEEDED(factory->GetImage(sz, static_cast<SIIGBF>(0x05), &hBmp)) && hBmp)
        out = qimageFromHBitmap(hBmp);
    factory->Release();
    return out;
}

static QImage extractViaPrivateIcons(const QString& iconPath, int iconIdx)
{
    if (iconPath.isEmpty())
        return {};
    using FnPrivateExtractIconsW = UINT(WINAPI*)(LPCWSTR, int, int, int, HICON*, UINT*, UINT, UINT);
    HMODULE u32 = GetModuleHandleW(L"user32.dll");
    auto fnPriv = u32
        ? reinterpret_cast<FnPrivateExtractIconsW>(GetProcAddress(u32, "PrivateExtractIconsW"))
        : nullptr;
    if (fnPriv) {
        for (int req : { 256, 128, 64, 48 }) {
            HICON hIcon = nullptr;
            UINT iconId = 0;
            const UINT got = fnPriv(reinterpret_cast<const wchar_t*>(iconPath.utf16()),
                                    iconIdx, req, req, &hIcon, &iconId, 1, 0);
            if (got > 0 && hIcon) {
                QImage img = qimageFromHIconDestroy(hIcon);
                if (!img.isNull())
                    return img;
            }
        }
    }
    HICON hLarge = nullptr;
    if (ExtractIconExW(reinterpret_cast<const wchar_t*>(iconPath.utf16()),
                       iconIdx, &hLarge, nullptr, 1) > 0 && hLarge) {
        QImage img = qimageFromHIconDestroy(hLarge);
        if (!img.isNull())
            return img;
    }
    return {};
}

static QImage imageFromImageListIndex(int sysIconIndex)
{
    if (sysIconIndex < 0)
        return {};
    static const IID kIID_IImageList = {
        0x46EB5926, 0x582E, 0x4017, {0x9F, 0xDF, 0xE8, 0x99, 0x8D, 0xAA, 0x09, 0x50}
    };

    auto fetchShil = [&](int shil) -> QImage {
        IImageList* imgList = nullptr;
        if (SUCCEEDED(SHGetImageList(shil, kIID_IImageList,
                                     reinterpret_cast<void**>(&imgList))) && imgList) {
            HICON hIcon = nullptr;
            const HRESULT hr = imgList->GetIcon(sysIconIndex, ILD_TRANSPARENT, &hIcon);
            imgList->Release();
            if (SUCCEEDED(hr) && hIcon)
                return qimageFromHIconDestroy(hIcon);
        }
        return {};
    };

    QImage jumbo = fetchShil(SHIL_JUMBO);
    const QRect jumboBox = findContentBoundingBox(jumbo);
    if (!jumbo.isNull() && !jumboBox.isEmpty() && qMax(jumboBox.width(), jumboBox.height()) > 48)
        return normalizeIconImage(jumbo);

    QImage extra = fetchShil(SHIL_EXTRALARGE);
    const QRect extraBox = findContentBoundingBox(extra);
    const int jumboArea = jumboBox.width() * jumboBox.height();
    const int extraArea = extraBox.width() * extraBox.height();

    if (!extra.isNull() && extraArea >= jumboArea)
        return normalizeIconImage(extra);
    if (!jumbo.isNull())
        return normalizeIconImage(jumbo);
    return normalizeIconImage(extra);
}

static QImage extractViaShGetFileInfo(const QString& nativePath, UINT extraFlags = 0, DWORD fileAttrs = 0)
{
    if (nativePath.isEmpty())
        return {};

    SHFILEINFOW sfi = {};
    const DWORD_PTR ok = SHGetFileInfoW(
        reinterpret_cast<const wchar_t*>(nativePath.utf16()),
        fileAttrs, &sfi, sizeof(sfi),
        SHGFI_SYSICONINDEX | extraFlags);

    if (ok) {
        QImage img = imageFromImageListIndex(sfi.iIcon);
        if (!img.isNull())
            return img;
    }

    ZeroMemory(&sfi, sizeof(sfi));
    if (SHGetFileInfoW(reinterpret_cast<const wchar_t*>(nativePath.utf16()),
                       fileAttrs, &sfi, sizeof(sfi),
                       SHGFI_ICON | SHGFI_LARGEICON | extraFlags) && sfi.hIcon) {
        return normalizeIconImage(qimageFromHIconDestroy(sfi.hIcon));
    }
    return {};
}

static QImage extractViaShellLink(const QString& lnkPath)
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
        return {};
    }

    QImage result;
    IPersistFile* ppf = nullptr;
    if (SUCCEEDED(psl->QueryInterface(kIID_IPersistFile, reinterpret_cast<void**>(&ppf))) && ppf) {
        if (SUCCEEDED(ppf->Load(reinterpret_cast<const wchar_t*>(lnkPath.utf16()), STGM_READ))) {
            wchar_t iconLoc[MAX_PATH] = {};
            int iconIdx = 0;
            if (SUCCEEDED(psl->GetIconLocation(iconLoc, MAX_PATH, &iconIdx)) && iconLoc[0] != L'\0') {
                const QString resolvedIconLoc = resolveExecutablePath(QString::fromWCharArray(iconLoc));
                if (!resolvedIconLoc.isEmpty()) {
                    result = extractViaPrivateIcons(resolvedIconLoc, iconIdx);
                    if (result.isNull())
                        result = extractViaShGetFileInfo(resolvedIconLoc);
                }
            }

            if (result.isNull()) {
                wchar_t targetBuf[MAX_PATH] = {};
                if (SUCCEEDED(psl->GetPath(targetBuf, MAX_PATH, nullptr, 0)) && targetBuf[0] != L'\0') {
                    const QString targetExe = resolveExecutablePath(QString::fromWCharArray(targetBuf));
                    result = extractViaShGetFileInfo(targetExe);
                }
            }
            if (result.isNull()) {
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
    return normalizeIconImage(result);
}

static QImage extractViaInternetShortcut(const QString& urlPath)
{
    wchar_t iconBuf[MAX_PATH * 2] = {};
    GetPrivateProfileStringW(
        L"InternetShortcut", L"IconFile", L"",
        iconBuf, MAX_PATH * 2,
        reinterpret_cast<const wchar_t*>(urlPath.utf16()));
    QString iconFile = expandEnvVars(QString::fromWCharArray(iconBuf).trimmed());
    if (iconFile.size() >= 2 && iconFile.startsWith(QLatin1Char('"')) && iconFile.endsWith(QLatin1Char('"')))
        iconFile = iconFile.mid(1, iconFile.size() - 2);
    if (!iconFile.isEmpty()) {
        QFileInfo icFi(iconFile);
        if (icFi.isRelative())
            iconFile = QFileInfo(urlPath).dir().absoluteFilePath(iconFile);
        iconFile = QDir::toNativeSeparators(iconFile);
        if (QFileInfo::exists(iconFile)) {
            const int iconIdx = static_cast<int>(GetPrivateProfileIntW(
                L"InternetShortcut", L"IconIndex", 0,
                reinterpret_cast<const wchar_t*>(urlPath.utf16())));
            const QString low = iconFile.toLower();
            if (low.endsWith(QStringLiteral(".png")) || low.endsWith(QStringLiteral(".jpg"))
                || low.endsWith(QStringLiteral(".jpeg")) || low.endsWith(QStringLiteral(".bmp"))) {
                QImage direct(iconFile);
                if (!direct.isNull())
                    return normalizeIconImage(direct);
            }
            QImage priv = extractViaPrivateIcons(iconFile, iconIdx);
            if (!priv.isNull())
                return normalizeIconImage(priv);
            QImage sh = extractViaShGetFileInfo(iconFile);
            if (!sh.isNull())
                return sh;
        }
    }
    return {};
}

static QImage extractBestIconImage(const QString& target)
{
    const QString resolved = resolveExecutablePath(target);
    if (resolved.isEmpty())
        return {};

    if (resolved.startsWith(QStringLiteral("ms-settings:"), Qt::CaseInsensitive)) {
        const wchar_t* sysSettings = L"C:\\Windows\\ImmersiveControlPanel\\SystemSettings.exe";
        if (GetFileAttributesW(sysSettings) != INVALID_FILE_ATTRIBUTES) {
            QImage img = extractViaShGetFileInfo(QString::fromWCharArray(sysSettings));
            if (!img.isNull())
                return img;
        }
        QImage img = extractViaPrivateIcons(QStringLiteral("shell32.dll"), 316);
        if (!img.isNull())
            return normalizeIconImage(img);
    }

    // UWP / MSIX / shell:AppsFolder targets: prefer IShellItemImageFactory for crisp Store app icons
    if (resolved.startsWith(QStringLiteral("shell:"), Qt::CaseInsensitive)) {
        QImage factoryImg = extractViaShellItemImageFactory(resolved, 256);
        if (!factoryImg.isNull())
            return normalizeIconImage(factoryImg);

        PIDLIST_ABSOLUTE pidl = nullptr;
        if (SUCCEEDED(SHParseDisplayName(reinterpret_cast<const wchar_t*>(resolved.utf16()),
                                         nullptr, &pidl, 0, nullptr)) && pidl) {
            SHFILEINFOW sfi = {};
            QImage img;
            if (SHGetFileInfoW(reinterpret_cast<LPCWSTR>(pidl), 0, &sfi, sizeof(sfi),
                               SHGFI_PIDL | SHGFI_SYSICONINDEX)) {
                img = imageFromImageListIndex(sfi.iIcon);
            }
            if (img.isNull()) {
                ZeroMemory(&sfi, sizeof(sfi));
                if (SHGetFileInfoW(reinterpret_cast<LPCWSTR>(pidl), 0, &sfi, sizeof(sfi),
                                   SHGFI_PIDL | SHGFI_ICON | SHGFI_LARGEICON) && sfi.hIcon) {
                    img = normalizeIconImage(qimageFromHIconDestroy(sfi.hIcon));
                }
            }
            CoTaskMemFree(pidl);
            if (!img.isNull())
                return img;
        }
    }

    if (resolved.endsWith(QStringLiteral(".url"), Qt::CaseInsensitive)) {
        QImage urlImg = extractViaInternetShortcut(resolved);
        if (!urlImg.isNull())
            return urlImg;
    }

    if (resolved.endsWith(QStringLiteral(".lnk"), Qt::CaseInsensitive)) {
        QImage lnkImg = extractViaShellLink(resolved);
        if (!lnkImg.isNull())
            return lnkImg;
    }

    if (QImage shImg = extractViaShGetFileInfo(resolved); !shImg.isNull())
        return shImg;

    if (resolved.endsWith(QStringLiteral(".exe"), Qt::CaseInsensitive)
        || resolved.endsWith(QStringLiteral(".lnk"), Qt::CaseInsensitive)
        || resolved.endsWith(QStringLiteral(".msc"), Qt::CaseInsensitive)) {
        if (QImage attrImg = extractViaShGetFileInfo(resolved, SHGFI_USEFILEATTRIBUTES, FILE_ATTRIBUTE_NORMAL); !attrImg.isNull())
            return attrImg;
    }

    return {};
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
    img = normalizeIconImage(extractBestIconImage(cleanPath));
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
    } else if (img.width() < 64 && img.height() < 64) {
        img = img.scaled(96, 96, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }

    if (size)
        *size = img.size();
    return img;
}
