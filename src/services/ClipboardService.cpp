#include "ClipboardService.h"

#include <QBuffer>
#include <QClipboard>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QMimeData>
#include <QStandardPaths>
#include <QUrl>
#include <QVariantMap>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

namespace {
LRESULT CALLBACK clipWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (msg == WM_CLIPBOARDUPDATE) {
        auto* svc = reinterpret_cast<ClipboardService*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
        if (svc)
            svc->handleClipboardUpdate();
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}
} // namespace
#endif

namespace {

constexpr int kMaxClipboardEntries = 100;

QString formatImageLabel(int w, int h, qint64 bytes)
{
    if (bytes >= 1048576) {
        const double mib = static_cast<double>(bytes) / 1048576.0;
        const QString num = (mib >= 10.0)
            ? QString::number(qRound(mib))
            : QString::number(mib, 'f', 1);
        return QStringLiteral("Image \u00B7 %1 MiB png %2x%3").arg(num).arg(w).arg(h);
    }
    const qint64 kib = qMax<qint64>(1, (bytes + 512) / 1024);
    return QStringLiteral("Image \u00B7 %1 KiB png %2x%3").arg(kib).arg(w).arg(h);
}

} // namespace

ClipboardService::ClipboardService(QObject* parent)
    : QObject(parent)
{
    const QString tmpRoot = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    if (!tmpRoot.isEmpty()) {
        m_tempDir = QDir(tmpRoot).filePath(QStringLiteral("SekaiDesk/clip"));
        QDir dir(m_tempDir);
        if (dir.exists()) {
            const QStringList stale = dir.entryList({ QStringLiteral("clip_*.png") }, QDir::Files);
            for (const QString& f : stale)
                dir.remove(f);
        } else {
            QDir().mkpath(m_tempDir);
        }
    }

#ifdef Q_OS_WIN
    const wchar_t* clsName = L"SekaiDeskClipboardListener";
    WNDCLASSW wc{};
    wc.lpfnWndProc = clipWndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = clsName;
    RegisterClassW(&wc);

    HWND hwnd = CreateWindowExW(0, clsName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
    if (hwnd) {
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
        AddClipboardFormatListener(hwnd);
        m_hwnd = hwnd;
    }
#endif
    captureClipboard(true);
}

ClipboardService::~ClipboardService()
{
    for (const QVariant& v : m_history)
        removeBackingFile(v.toMap());

#ifdef Q_OS_WIN
    if (m_hwnd) {
        HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
        RemoveClipboardFormatListener(hwnd);
        DestroyWindow(hwnd);
        m_hwnd = nullptr;
    }
#endif
}

void ClipboardService::removeBackingFile(const QVariantMap& item)
{
    if (!item.value(QStringLiteral("isImage")).toBool())
        return;
    const QString p = item.value(QStringLiteral("imagePath")).toString();
    if (!p.isEmpty())
        QFile::remove(p);
}

void ClipboardService::handleClipboardUpdate()
{
    captureClipboard(false);
}

void ClipboardService::captureClipboard(bool initial)
{
    Q_UNUSED(initial);
    QClipboard* cb = QGuiApplication::clipboard();
    if (!cb)
        return;

    const QMimeData* mime = cb->mimeData();
    if (mime && mime->hasImage()) {
        const QImage img = cb->image();
        if (!img.isNull() && !m_tempDir.isEmpty()) {
            QByteArray pngBytes;
            {
                QBuffer buf(&pngBytes);
                buf.open(QIODevice::WriteOnly);
                img.save(&buf, "PNG");
            }
            if (!pngBytes.isEmpty()) {
                const QString hash = QString::fromLatin1(
                    QCryptographicHash::hash(pngBytes, QCryptographicHash::Sha1).toHex());
                if (!m_suppressImageHash.isEmpty() && hash == m_suppressImageHash) {
                    m_suppressImageHash.clear();
                    return;
                }
                m_suppressImageHash.clear();
                m_suppressText.clear();

                bool wasPinned = false;
                QString reusedPath;
                for (int i = m_history.size() - 1; i >= 0; --i) {
                    const QVariantMap item = m_history.at(i).toMap();
                    if (item.value(QStringLiteral("isImage")).toBool() &&
                        item.value(QStringLiteral("hash")).toString() == hash) {
                        if (i == 0)
                            return;
                        wasPinned = item.value(QStringLiteral("pinned")).toBool();
                        reusedPath = item.value(QStringLiteral("imagePath")).toString();
                        m_history.removeAt(i);
                        break;
                    }
                }

                QString savePath = reusedPath;
                if (savePath.isEmpty() || !QFile::exists(savePath)) {
                    QDir().mkpath(m_tempDir);
                    savePath = QDir(m_tempDir).filePath(
                        QStringLiteral("clip_%1_%2.png")
                            .arg(QDateTime::currentMSecsSinceEpoch())
                            .arg(++m_nextId));
                    QFile f(savePath);
                    if (!f.open(QIODevice::WriteOnly))
                        return;
                    f.write(pngBytes);
                    f.close();
                }

                QVariantMap entry;
                entry.insert(QStringLiteral("id"), QStringLiteral("c_%1").arg(++m_nextId));
                entry.insert(QStringLiteral("isImage"), true);
                entry.insert(QStringLiteral("imagePath"), savePath);
                entry.insert(QStringLiteral("imageUrl"), QUrl::fromLocalFile(savePath).toString());
                entry.insert(QStringLiteral("imageWidth"), img.width());
                entry.insert(QStringLiteral("imageHeight"), img.height());
                entry.insert(QStringLiteral("imageBytes"), static_cast<qint64>(pngBytes.size()));
                entry.insert(QStringLiteral("hash"), hash);
                entry.insert(QStringLiteral("text"), QString());
                entry.insert(QStringLiteral("preview"),
                             formatImageLabel(img.width(), img.height(), pngBytes.size()));
                entry.insert(QStringLiteral("time"),
                             QDateTime::currentDateTime().toString(QStringLiteral("HH:mm")));
                entry.insert(QStringLiteral("chars"), 0);
                entry.insert(QStringLiteral("pinned"), wasPinned);

                if (wasPinned) {
                    m_history.prepend(entry);
                } else {
                    int insertAt = 0;
                    while (insertAt < m_history.size() &&
                           m_history.at(insertAt).toMap().value(QStringLiteral("pinned")).toBool()) {
                        ++insertAt;
                    }
                    m_history.insert(insertAt, entry);
                }

                while (m_history.size() > kMaxClipboardEntries) {
                    int lastUnpinned = -1;
                    for (int i = m_history.size() - 1; i >= 0; --i) {
                        if (!m_history.at(i).toMap().value(QStringLiteral("pinned")).toBool()) {
                            lastUnpinned = i;
                            break;
                        }
                    }
                    if (lastUnpinned < 0)
                        break;
                    removeBackingFile(m_history.at(lastUnpinned).toMap());
                    m_history.removeAt(lastUnpinned);
                }

                emit historyChanged();
                return;
            }
        }
    }

    const QString text = cb->text();
    if (text.trimmed().isEmpty() || text.size() > 200000)
        return;

    if (!m_suppressText.isEmpty() && text == m_suppressText) {
        m_suppressText.clear();
        return;
    }
    m_suppressText.clear();
    m_suppressImageHash.clear();

    bool wasPinned = false;
    for (int i = m_history.size() - 1; i >= 0; --i) {
        const QVariantMap item = m_history.at(i).toMap();
        if (!item.value(QStringLiteral("isImage")).toBool() &&
            item.value(QStringLiteral("text")).toString() == text) {
            if (i == 0)
                return;
            wasPinned = item.value(QStringLiteral("pinned")).toBool();
            m_history.removeAt(i);
            break;
        }
    }

    QString preview = text.simplified();
    if (preview.size() > 140)
        preview = preview.left(137) + QStringLiteral("...");

    QVariantMap entry;
    entry.insert(QStringLiteral("id"), QStringLiteral("c_%1").arg(++m_nextId));
    entry.insert(QStringLiteral("isImage"), false);
    entry.insert(QStringLiteral("imagePath"), QString());
    entry.insert(QStringLiteral("imageUrl"), QString());
    entry.insert(QStringLiteral("imageWidth"), 0);
    entry.insert(QStringLiteral("imageHeight"), 0);
    entry.insert(QStringLiteral("imageBytes"), 0);
    entry.insert(QStringLiteral("hash"), QString());
    entry.insert(QStringLiteral("text"), text);
    entry.insert(QStringLiteral("preview"), preview);
    entry.insert(QStringLiteral("time"), QDateTime::currentDateTime().toString(QStringLiteral("HH:mm")));
    entry.insert(QStringLiteral("chars"), text.size());
    entry.insert(QStringLiteral("pinned"), wasPinned);

    // Insert pinned items before unpinned, or at top for new unpinned item
    if (wasPinned) {
        m_history.prepend(entry);
    } else {
        int insertAt = 0;
        while (insertAt < m_history.size() && m_history.at(insertAt).toMap().value(QStringLiteral("pinned")).toBool())
            ++insertAt;
        m_history.insert(insertAt, entry);
    }

    while (m_history.size() > kMaxClipboardEntries) {
        int lastUnpinned = -1;
        for (int i = m_history.size() - 1; i >= 0; --i) {
            if (!m_history.at(i).toMap().value(QStringLiteral("pinned")).toBool()) {
                lastUnpinned = i;
                break;
            }
        }
        if (lastUnpinned < 0)
            break;
        removeBackingFile(m_history.at(lastUnpinned).toMap());
        m_history.removeAt(lastUnpinned);
    }

    emit historyChanged();
}

void ClipboardService::copyIndex(int index)
{
    if (index < 0 || index >= m_history.size())
        return;
    const QVariantMap item = m_history.at(index).toMap();
    if (item.value(QStringLiteral("isImage")).toBool()) {
        const QString imgPath = item.value(QStringLiteral("imagePath")).toString();
        QImage img(imgPath);
        if (!img.isNull()) {
            if (QClipboard* cb = QGuiApplication::clipboard()) {
                m_suppressImageHash = item.value(QStringLiteral("hash")).toString();
                cb->setImage(img);
            }
        }
        return;
    }
    copyText(item.value(QStringLiteral("text")).toString());
}

void ClipboardService::copyText(const QString& text)
{
    QClipboard* cb = QGuiApplication::clipboard();
    if (!cb || text.isEmpty())
        return;
    m_suppressText = text;
    cb->setText(text);
}

void ClipboardService::togglePin(int index)
{
    if (index < 0 || index >= m_history.size())
        return;
    QVariantMap item = m_history.at(index).toMap();
    const bool nextPin = !item.value(QStringLiteral("pinned")).toBool();
    item.insert(QStringLiteral("pinned"), nextPin);
    m_history.removeAt(index);
    if (nextPin) {
        m_history.prepend(item);
    } else {
        int insertAt = 0;
        while (insertAt < m_history.size() && m_history.at(insertAt).toMap().value(QStringLiteral("pinned")).toBool())
            ++insertAt;
        m_history.insert(insertAt, item);
    }
    emit historyChanged();
}

void ClipboardService::removeIndex(int index)
{
    if (index < 0 || index >= m_history.size())
        return;
    removeBackingFile(m_history.at(index).toMap());
    m_history.removeAt(index);
    emit historyChanged();
}

void ClipboardService::clearUnpinned()
{
    for (int i = m_history.size() - 1; i >= 0; --i) {
        const QVariantMap item = m_history.at(i).toMap();
        if (!item.value(QStringLiteral("pinned")).toBool()) {
            removeBackingFile(item);
            m_history.removeAt(i);
        }
    }
    emit historyChanged();
}
