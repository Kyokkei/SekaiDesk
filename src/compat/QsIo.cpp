#include "QsIo.h"

#include <QFile>
#include <QIODevice>
#include <QUrl>

// ---------------------------------------------------------------------------
// QsStdioCollector
// ---------------------------------------------------------------------------

QsStdioCollector::QsStdioCollector(QObject* parent)
    : QObject(parent)
{
}

void QsStdioCollector::append(const QByteArray& bytes)
{
    if (bytes.isEmpty())
        return;
    m_text += QString::fromUtf8(bytes);
    emit textChanged();
}

void QsStdioCollector::finish()
{
    emit streamFinished();
}

void QsStdioCollector::reset()
{
    if (m_text.isEmpty())
        return;
    m_text.clear();
    emit textChanged();
}

// ---------------------------------------------------------------------------
// QsProcess
// ---------------------------------------------------------------------------

QsProcess::QsProcess(QObject* parent)
    : QObject(parent)
{
    connect(&m_proc, &QProcess::started, this, [this]() {
        setRunning(true);
        emit started();
    });
    connect(&m_proc, &QProcess::readyReadStandardOutput, this, [this]() {
        if (auto* c = asCollector(m_stdoutTarget))
            c->append(m_proc.readAllStandardOutput());
    });
    connect(&m_proc, &QProcess::readyReadStandardError, this, [this]() {
        if (auto* c = asCollector(m_stderrTarget))
            c->append(m_proc.readAllStandardError());
    });
    connect(&m_proc, &QProcess::finished, this, &QsProcess::handleFinished);
    connect(&m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            qWarning("Process: failed to start: %s",
                     qPrintable(m_command.value(0).toString()));
            setRunning(false);
            // Consumers expect streamFinished even on failure.
            if (auto* c = asCollector(m_stdoutTarget))
                c->finish();
            if (auto* c = asCollector(m_stderrTarget))
                c->finish();
            emit exited(-1);
        }
    });
}

QVariantList QsProcess::command() const
{
    return m_command;
}

void QsProcess::setCommand(const QVariantList& command)
{
    if (m_command == command)
        return;
    m_command = command;
    emit commandChanged();
}

QString QsProcess::cwd() const
{
    return m_cwd;
}

void QsProcess::setCwd(const QString& cwd)
{
    QString path = cwd;
    if (path.startsWith(QStringLiteral("file://")))
        path = QUrl(path).toLocalFile();
    if (m_cwd == path)
        return;
    m_cwd = path;
    emit cwdChanged();
}

bool QsProcess::running() const
{
    return m_running;
}

QObject* QsProcess::stdoutTarget() const
{
    return m_stdoutTarget;
}

void QsProcess::setStdoutTarget(QObject* target)
{
    m_stdoutTarget = target;
}

QObject* QsProcess::stderrTarget() const
{
    return m_stderrTarget;
}

void QsProcess::setStderrTarget(QObject* target)
{
    m_stderrTarget = target;
}

QsStdioCollector* QsProcess::asCollector(QObject* target) const
{
    return qobject_cast<QsStdioCollector*>(target);
}

void QsProcess::setRunning(bool running)
{
    if (m_running == running)
        return;
    m_running = running;
    emit runningChanged();
}

void QsProcess::start()
{
    if (m_command.isEmpty()) {
        qWarning("Process: empty command");
        return;
    }

    if (m_proc.state() != QProcess::NotRunning)
        m_proc.waitForFinished(100);

    if (auto* c = asCollector(m_stdoutTarget))
        c->reset();
    if (auto* c = asCollector(m_stderrTarget))
        c->reset();

    QStringList args;
    args.reserve(m_command.size());
    for (const QVariant& v : m_command) {
        QString s = v.toString();
        if (s.startsWith(QStringLiteral("file://")))
            s = QUrl(s).toLocalFile();
        args << s;
    }

    if (!m_cwd.isEmpty())
        m_proc.setWorkingDirectory(m_cwd);

    setRunning(true); // optimistic; corrected by started()/errorOccurred()
    if (args.size() == 1)
        m_proc.start(args.first());
    else
        m_proc.start(args.first(), args.sliced(1));
}

void QsProcess::kill()
{
    if (m_proc.state() != QProcess::NotRunning)
        m_proc.kill();
}

void QsProcess::handleFinished(int exitCode, QProcess::ExitStatus status)
{
    // Flush whatever is still buffered.
    if (auto* c = asCollector(m_stdoutTarget))
        c->append(m_proc.readAllStandardOutput());
    if (auto* c = asCollector(m_stderrTarget))
        c->append(m_proc.readAllStandardError());

    setRunning(false);

    if (auto* c = asCollector(m_stdoutTarget))
        c->finish();
    if (auto* c = asCollector(m_stderrTarget))
        c->finish();

    const int code = (status == QProcess::CrashExit) ? -1 : exitCode;
    emit exited(code);
}

// ---------------------------------------------------------------------------
// QsFileView
// ---------------------------------------------------------------------------

QsFileView::QsFileView(QObject* parent)
    : QObject(parent)
{
}

void QsFileView::setPath(const QString& path)
{
    QString p = path;
    if (p.startsWith(QStringLiteral("file://")))
        p = QUrl(p).toLocalFile();

    if (m_path == p)
        return;
    m_path = p;
    emit pathChanged();
    loadFromDisk();
}

void QsFileView::setText(const QString& text)
{
    if (m_text == text)
        return;
    m_text = text;
    emit textChanged();
}

void QsFileView::loadFromDisk()
{
    if (m_path.isEmpty()) {
        setLoaded(false);
        return;
    }

    QFile file(m_path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_text.clear();
        emit textChanged();
        setLoaded(false);
        return;
    }
    m_text = QString::fromUtf8(file.readAll());
    emit textChanged();
    setLoaded(true);
}

void QsFileView::setLoaded(bool loaded)
{
    if (m_loaded == loaded)
        return;
    m_loaded = loaded;
    emit loadedChanged();
    if (loaded)
        emit loaded();
}

bool QsFileView::save()
{
    if (m_path.isEmpty()) {
        qWarning("FileView: save() with no path");
        return false;
    }

    QFile file(m_path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning("FileView: cannot write %s: %s",
                 qPrintable(m_path), qPrintable(file.errorString()));
        return false;
    }
    file.write(m_text.toUtf8());
    file.close();
    emit saved();
    return true;
}

void QsFileView::reload()
{
    loadFromDisk();
}
