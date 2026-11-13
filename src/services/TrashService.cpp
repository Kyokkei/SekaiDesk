#include "TrashService.h"

#ifdef Q_OS_WIN
#include <windows.h>
#include <shellapi.h>
#endif

TrashService::TrashService(QObject* parent)
    : QObject(parent)
{
    m_timer.setInterval(2000);
    connect(&m_timer, &QTimer::timeout, this, &TrashService::refresh);
    m_timer.start();
    QTimer::singleShot(200, this, &TrashService::refresh);
}

void TrashService::refresh()
{
#ifdef Q_OS_WIN
    SHQUERYRBINFO info = {};
    info.cbSize = sizeof(info);
    qint64 nextCount = m_itemCount;
    if (SUCCEEDED(SHQueryRecycleBinW(nullptr, &info)))
        nextCount = static_cast<qint64>(info.i64NumItems);

    if (nextCount != m_itemCount) {
        m_itemCount = nextCount;
        emit stateChanged();
    }
#endif
}

void TrashService::openBin()
{
#ifdef Q_OS_WIN
    ShellExecuteW(nullptr, L"open", L"shell:RecycleBinFolder",
                  nullptr, nullptr, SW_SHOWNORMAL);
#endif
}

void TrashService::emptyBin()
{
#ifdef Q_OS_WIN
    SHEmptyRecycleBinW(nullptr, nullptr, 0);
    refresh();
#endif
}
