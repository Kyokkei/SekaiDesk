#include "QsCore.h"

#include <QCoreApplication>
#include <QDir>
#include <QGuiApplication>
#include <QProcessEnvironment>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTime>

// ---------------------------------------------------------------------------
// QsGlobal
// ---------------------------------------------------------------------------

QsGlobal::QsGlobal(QObject* parent)
    : QObject(parent)
{
    m_shellDir = resolveShellDir();
    connect(qGuiApp, &QGuiApplication::screenAdded, this, &QsGlobal::screensChanged);
    connect(qGuiApp, &QGuiApplication::screenRemoved, this, &QsGlobal::screensChanged);
    connect(qGuiApp, &QGuiApplication::primaryScreenChanged, this, &QsGlobal::screensChanged);
}

QsGlobal* QsGlobal::instance()
{
    static QsGlobal g;
    return &g;
}

QList<QScreen*> QsGlobal::screens() const
{
    return QGuiApplication::screens();
}

QVariantMap QsGlobal::env() const
{
    const QProcessEnvironment e = QProcessEnvironment::systemEnvironment();
    QVariantMap out;
    const QStringList keys = e.keys();
    for (const QString& k : keys)
        out.insert(k, e.value(k));
    return out;
}

QString QsGlobal::resolveShellDir()
{
    // Explicit override wins (portable deployment / dev layouts).
    QString shell = qEnvironmentVariable("SEKAIDESK_SHELL_DIR");
    if (!shell.isEmpty() && QDir(shell).exists())
        return QDir::cleanPath(shell);

    // Layout A: exe in <repo>/build[...]/  -> <repo>/SekaiPop/sekaipop
    // Layout B: portable zip: <root>/SekaiDesk.exe + <root>/SekaiPop/sekaipop
    const QDir appDir(QCoreApplication::applicationDirPath());
    const QStringList candidates = {
        appDir.absoluteFilePath(QStringLiteral("../SekaiPop/sekaipop")),
        appDir.absoluteFilePath(QStringLiteral("SekaiPop/sekaipop")),
        appDir.absoluteFilePath(QStringLiteral("../../SekaiPop/sekaipop")),
    };
    for (const QString& c : candidates) {
        if (QDir(c).exists())
            return QDir::cleanPath(c);
    }
    return QString();
}

// ---------------------------------------------------------------------------
// SystemClock
// ---------------------------------------------------------------------------

SystemClock::SystemClock(QObject* parent)
    : QObject(parent)
{
    connect(&m_timer, &QTimer::timeout, this, &SystemClock::tick);
    tick();
    m_timer.start(1000);
}

SystemClock* SystemClock::instance()
{
    static SystemClock c;
    return &c;
}

void SystemClock::tick()
{
    const QTime t = QTime::currentTime();
    const bool changed = (t.hour() != m_hours) || (t.minute() != m_minutes)
        || (t.second() != m_seconds);
    m_hours = t.hour();
    m_minutes = t.minute();
    m_seconds = t.second();
    if (changed)
        emit timeChanged();
}

// ---------------------------------------------------------------------------
// Variants
// ---------------------------------------------------------------------------

Variants::Variants(QObject* parent)
    : QObject(parent)
{
}

Variants::~Variants()
{
    for (const QPointer<QObject>& inst : m_instances) {
        if (inst)
            inst->deleteLater();
    }
}

void Variants::setModel(const QVariant& model)
{
    if (m_model == model)
        return;
    m_model = model;
    emit modelChanged();
    rebuild();
}

void Variants::setDelegate(QQmlComponent* delegate)
{
    if (m_delegate == delegate)
        return;
    m_delegate = delegate;
    emit delegateChanged();
    rebuild();
}

void Variants::rebuild()
{
    if (m_rebuilding)
        return;
    m_rebuilding = true;

    for (const QPointer<QObject>& inst : m_instances) {
        if (inst)
            inst->deleteLater();
    }
    m_instances.clear();

    QVariantList entries;
    if (m_model.canConvert<QVariantList>())
        entries = m_model.toList();

    if (m_delegate && m_delegate->isReady()) {
        QQmlEngine* engine = qmlEngine(this);
        for (const QVariant& entry : entries) {
            QQmlContext* ctx = new QQmlContext(qmlContext(this), this);
            ctx->setContextProperty(QStringLiteral("modelData"), entry);
            ctx->setContextProperty(QStringLiteral("variant"), entry);

            QObject* inst = m_delegate->create(ctx);
            if (!inst) {
                qWarning("Variants: delegate creation failed: %s",
                         qPrintable(m_delegate->errorString()));
                delete ctx;
                continue;
            }
            QQmlEngine::setObjectOwnership(inst, QQmlEngine::CppOwnership);
            inst->setParent(this);
            // Keep the context alive with the instance: the context must
            // outlive the object, but the instance's parent chain (window
            // hierarchy) is not this object, so track it separately.
            connect(inst, &QObject::destroyed, this, [ctx]() { ctx->deleteLater(); });
            m_instances.append(inst);
        }
    }

    m_rebuilding = false;
}
