#include "ClipboardService.h"

#include <QClipboard>
#include <QDateTime>
#include <QGuiApplication>
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

ClipboardService::ClipboardService(QObject* parent)
    : QObject(parent)
{
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
#ifdef Q_OS_WIN
    if (m_hwnd) {
        HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
        RemoveClipboardFormatListener(hwnd);
        DestroyWindow(hwnd);
        m_hwnd = nullptr;
    }
#endif
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
    const QString text = cb->text();
    if (text.trimmed().isEmpty() || text.size() > 200000)
        return;

    if (!m_suppressText.isEmpty() && text == m_suppressText) {
        m_suppressText.clear();
        return;
    }
    m_suppressText.clear();

    bool wasPinned = false;
    for (int i = m_history.size() - 1; i >= 0; --i) {
        const QVariantMap item = m_history.at(i).toMap();
        if (item.value(QStringLiteral("text")).toString() == text) {
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

    while (m_history.size() > 35) {
        int lastUnpinned = -1;
        for (int i = m_history.size() - 1; i >= 0; --i) {
            if (!m_history.at(i).toMap().value(QStringLiteral("pinned")).toBool()) {
                lastUnpinned = i;
                break;
            }
        }
        if (lastUnpinned < 0)
            break;
        m_history.removeAt(lastUnpinned);
    }

    emit historyChanged();
}

void ClipboardService::copyIndex(int index)
{
    if (index < 0 || index >= m_history.size())
        return;
    copyText(m_history.at(index).toMap().value(QStringLiteral("text")).toString());
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
    m_history.removeAt(index);
    emit historyChanged();
}

void ClipboardService::clearUnpinned()
{
    for (int i = m_history.size() - 1; i >= 0; --i) {
        if (!m_history.at(i).toMap().value(QStringLiteral("pinned")).toBool())
            m_history.removeAt(i);
    }
    emit historyChanged();
}
