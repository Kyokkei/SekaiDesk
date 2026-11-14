#pragma once
// QsCore — compat layer for the Quickshell core module.
// Provides: Quickshell (global singleton), SystemClock, Variants.
// Registered manually in main.cpp under URI "Quickshell" 1.0.

#include <QObject>
#include <QPointer>
#include <QQmlComponent>
#include <QRect>
#include <QScreen>
#include <QTimer>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

class QGuiApplication;

// ---------------------------------------------------------------------------
// Quickshell global singleton: `Quickshell.screens`, `Quickshell.shellDir`,
// `Quickshell.env`. shellDir points at the vendored SekaiPop shell root.
// ---------------------------------------------------------------------------
class QsGlobal : public QObject {
    Q_OBJECT
    Q_PROPERTY(QList<QScreen*> screens READ screens NOTIFY screensChanged)
    Q_PROPERTY(QRect virtualGeometry READ virtualGeometry NOTIFY screensChanged)
    Q_PROPERTY(QString shellDir READ shellDir CONSTANT)
    Q_PROPERTY(QVariantMap env READ env CONSTANT)

public:
    static QsGlobal* instance();

    QList<QScreen*> screens() const;
    QRect virtualGeometry() const;
    QString shellDir() const { return m_shellDir; }
    QVariantMap env() const;

    static QString resolveShellDir();

signals:
    void screensChanged();

private:
    explicit QsGlobal(QObject* parent = nullptr);
    void watchScreen(QScreen* scr);
    QString m_shellDir;
};

// ---------------------------------------------------------------------------
// SystemClock singleton: ticks once per second, exposes hours/minutes/seconds
// and the current date. Matches the subset of Quickshell.SystemClock used by
// SekaiPop widgets.
// ---------------------------------------------------------------------------
class SystemClock : public QObject {
    Q_OBJECT
    Q_PROPERTY(int hours READ hours NOTIFY timeChanged)
    Q_PROPERTY(int minutes READ minutes NOTIFY timeChanged)
    Q_PROPERTY(int seconds READ seconds NOTIFY timeChanged)
    Q_PROPERTY(QDate date READ date NOTIFY dateChanged)

public:
    static SystemClock* instance();

    int hours() const { return m_hours; }
    int minutes() const { return m_minutes; }
    int seconds() const { return m_seconds; }
    QDate date() const { return QDate::currentDate(); }

signals:
    void timeChanged();
    void dateChanged();

private:
    explicit SystemClock(QObject* parent = nullptr);
    void tick();

    QTimer m_timer;
    int m_hours = 0;
    int m_minutes = 0;
    int m_seconds = 0;
};

// ---------------------------------------------------------------------------
// Variants: instantiates `delegate` once per entry of `model`, exposing the
// entry as `modelData` (and `variant` for compatibility) in the instance's
// context. Used by SekaiPop for per-monitor windows
// (`model: Quickshell.screens`).
// ---------------------------------------------------------------------------
class Variants : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariant model READ model WRITE setModel NOTIFY modelChanged)
    Q_PROPERTY(QQmlComponent* delegate READ delegate WRITE setDelegate NOTIFY delegateChanged)

public:
    explicit Variants(QObject* parent = nullptr);
    ~Variants() override;

    QVariant model() const { return m_model; }
    void setModel(const QVariant& model);

    QQmlComponent* delegate() const { return m_delegate; }
    void setDelegate(QQmlComponent* delegate);

signals:
    void modelChanged();
    void delegateChanged();

private:
    void rebuild();

    QVariant m_model;
    QQmlComponent* m_delegate = nullptr;
    QList<QPointer<QObject>> m_instances;
    bool m_rebuilding = false;
};
