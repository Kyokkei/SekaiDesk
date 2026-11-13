#include "MediaService.h"

#include <QJsonDocument>
#include <QJsonObject>

#ifdef Q_OS_WIN
#include <windows.h>

namespace {

static void sendMediaVk(WORD vk)
{
    INPUT inputs[2] = {};
    inputs[0].type = INPUT_KEYBOARD;
    inputs[0].ki.wVk = vk;
    inputs[1].type = INPUT_KEYBOARD;
    inputs[1].ki.wVk = vk;
    inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(2, inputs, sizeof(INPUT));
}

} // namespace
#endif

MediaService::MediaService(QObject* parent)
    : QObject(parent)
{
#ifdef Q_OS_WIN
    QTimer::singleShot(400, this, &MediaService::startWorker);
#endif
}

MediaService::~MediaService()
{
    if (m_proc) {
        m_proc->kill();
        m_proc->waitForFinished(300);
    }
}

void MediaService::playPause()
{
#ifdef Q_OS_WIN
    sendMediaVk(VK_MEDIA_PLAY_PAUSE);
#endif
}

void MediaService::next()
{
#ifdef Q_OS_WIN
    sendMediaVk(VK_MEDIA_NEXT_TRACK);
#endif
}

void MediaService::previous()
{
#ifdef Q_OS_WIN
    sendMediaVk(VK_MEDIA_PREV_TRACK);
#endif
}

void MediaService::startWorker()
{
#ifdef Q_OS_WIN
    if (m_proc)
        return;

    m_proc = new QProcess(this);
    m_proc->setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments* args) {
        args->flags |= CREATE_NO_WINDOW;
    });
    connect(m_proc, &QProcess::readyReadStandardOutput,
            this, &MediaService::onStdoutReady);

    const QString script = QStringLiteral(
        "$ErrorActionPreference = 'SilentlyContinue'\n"
        "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8\n"
        "Add-Type -AssemblyName System.Runtime.WindowsRuntime\n"
        "[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime] | Out-Null\n"
        "$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]\n"
        "function Await($op, $t) { $m = $asTask.MakeGenericMethod($t); $tsk = $m.Invoke($null, @($op)); $tsk.Wait(1500) | Out-Null; $tsk.Result }\n"
        "$mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])\n"
        "$last = ''\n"
        "while ($true) {\n"
        "  $obj = @{ has = $false; playing = $false; title = ''; artist = ''; app = '' }\n"
        "  if ($mgr) {\n"
        "    $s = $mgr.GetCurrentSession()\n"
        "    if ($s) {\n"
        "      $obj.has = $true\n"
        "      $obj.app = [string]$s.SourceAppUserModelId\n"
        "      $pb = $s.GetPlaybackInfo()\n"
        "      if ($pb) { $obj.playing = ($pb.PlaybackStatus -eq 'Playing') }\n"
        "      $pr = Await ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])\n"
        "      if ($pr) { $obj.title = [string]$pr.Title; $obj.artist = [string]$pr.Artist }\n"
        "    }\n"
        "  }\n"
        "  $line = ($obj | ConvertTo-Json -Compress)\n"
        "  if ($line -ne $last) { $last = $line; [Console]::Out.WriteLine($line); [Console]::Out.Flush() }\n"
        "  Start-Sleep -Milliseconds 1200\n"
        "}\n"
    );

    m_proc->start(QStringLiteral("powershell.exe"),
                  { QStringLiteral("-NoLogo"),
                    QStringLiteral("-NoProfile"),
                    QStringLiteral("-NonInteractive"),
                    QStringLiteral("-WindowStyle"), QStringLiteral("Hidden"),
                    QStringLiteral("-Command"), QStringLiteral("-") });
    if (m_proc->waitForStarted(1500)) {
        m_proc->write(script.toUtf8());
        m_proc->closeWriteChannel();
    }
#endif
}

void MediaService::onStdoutReady()
{
    if (!m_proc)
        return;
    m_buf.append(m_proc->readAllStandardOutput());
    int idx = -1;
    while ((idx = m_buf.indexOf('\n')) != -1) {
        const QByteArray line = m_buf.left(idx).trimmed();
        m_buf.remove(0, idx + 1);
        if (line.isEmpty())
            continue;
        const QJsonDocument doc = QJsonDocument::fromJson(line);
        if (!doc.isObject())
            continue;
        const QJsonObject obj = doc.object();
        applySnapshot(obj.value(QStringLiteral("has")).toBool(false),
                      obj.value(QStringLiteral("playing")).toBool(false),
                      obj.value(QStringLiteral("title")).toString(),
                      obj.value(QStringLiteral("artist")).toString(),
                      obj.value(QStringLiteral("app")).toString());
    }
}

void MediaService::applySnapshot(bool hasSession, bool isPlaying,
                                 const QString& title, const QString& artist,
                                 const QString& sourceApp)
{
    if (m_hasSession == hasSession
        && m_isPlaying == isPlaying
        && m_title == title
        && m_artist == artist
        && m_sourceApp == sourceApp) {
        return;
    }
    m_hasSession = hasSession;
    m_isPlaying = isPlaying;
    m_title = title;
    m_artist = artist;
    m_sourceApp = sourceApp;
    emit mediaChanged();
}
