#pragma once
// QsIo — compat layer for the Quickshell.Io module.
// Provides: Process, StdioCollector, FileView.
// Registered in main.cpp under URI "Quickshell.Io" 1.0.
//
// Scaffold scope: the API subset SekaiPop services actually use —
//   Process { command: [...]; stdout: StdioCollector { onStreamFinished: ... } }
//   FileView { path: ...; text: ... }

#include <QProcess>
#include <QQmlEngine>
#include <QObject>
#include <QString>

// MinGW defines stdout/stderr as macros; the QML property names need the raw
// identifiers. stdio remains available via <cstdio> elsewhere.
#undef stdout
#undef stderr

// ---------------------------------------------------------------------------
// StdioCollector: accumulates a stream's text; emits streamFinished() when
// the originating process (or pipe) closes the stream.
// ---------------------------------------------------------------------------
class QsStdioCollector : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString text READ text NOTIFY textChanged)

public:
    explicit QsStdioCollector(QObject* parent = nullptr);

    QString text() const { return m_text; }
    void append(const QByteArray& bytes);
    void finish();
    void reset();

signals:
    void textChanged();
    void streamFinished();

private:
    QString m_text;
};

// ---------------------------------------------------------------------------
// Process: thin wrapper over QProcess matching Quickshell's Process API.
// ---------------------------------------------------------------------------
class QsProcess : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList command READ command WRITE setCommand NOTIFY commandChanged)
    Q_PROPERTY(QString cwd READ cwd WRITE setCwd NOTIFY cwdChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QObject* stdout READ stdoutTarget WRITE setStdoutTarget)
    Q_PROPERTY(QObject* stderr READ stderrTarget WRITE setStderrTarget)

public:
    explicit QsProcess(QObject* parent = nullptr);

    QVariantList command() const { return m_command; }
    void setCommand(const QVariantList& command);

    QString cwd() const { return m_cwd; }
    void setCwd(const QString& cwd);

    bool running() const;

    QObject* stdoutTarget() const { return m_stdoutTarget; }
    void setStdoutTarget(QObject* target);

    QObject* stderrTarget() const { return m_stderrTarget; }
    void setStderrTarget(QObject* target);

    Q_INVOKABLE void start();
    Q_INVOKABLE void kill();
    // Quickshell API parity (kill with signal on POSIX; no-op wrapper here).
    Q_INVOKABLE void signal(int sig) { Q_UNUSED(sig); kill(); }

signals:
    void commandChanged();
    void cwdChanged();
    void runningChanged();
    void started();
    void exited(int exitCode);

private:
    QsStdioCollector* asCollector(QObject* target) const;
    void setRunning(bool running);
    void handleFinished(int exitCode, QProcess::ExitStatus status);

    QProcess m_proc;
    QVariantList m_command;
    QString m_cwd;
    QObject* m_stdoutTarget = nullptr;
    QObject* m_stderrTarget = nullptr;
    bool m_running = false;
};

// ---------------------------------------------------------------------------
// FileView: synchronous file text access. Loading happens on path assignment
// (emits loaded()); saving is explicit via save().
// ---------------------------------------------------------------------------
class QsFileView : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(QString text READ text WRITE setText NOTIFY textChanged)
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)

public:
    explicit QsFileView(QObject* parent = nullptr);

    QString path() const { return m_path; }
    void setPath(const QString& path);

    QString text() const { return m_text; }
    void setText(const QString& text);

    bool loaded() const { return m_loaded; }

    Q_INVOKABLE bool save();
    Q_INVOKABLE void reload();

signals:
    void pathChanged();
    void textChanged();
    void loadedChanged();
    void loaded();
    void saved();

private:
    void loadFromDisk();
    void setLoaded(bool loaded);

    QString m_path;
    QString m_text;
    bool m_loaded = false;
};
