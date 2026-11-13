#pragma once
// SystemControlService — Global Ctrl+Alt+A hotkey, DDC/CI monitor brightness
// (dxva2.dll), Windows Dark/Light theme toggle, and Power/Settings actions.

#include <QAbstractNativeEventFilter>
#include <QObject>
#include <QTimer>
#include <QVariantList>

class SystemControlService : public QObject, public QAbstractNativeEventFilter {
    Q_OBJECT
    Q_PROPERTY(bool brightnessSupported READ brightnessSupported NOTIFY stateChanged)
    Q_PROPERTY(int brightness READ brightness NOTIFY stateChanged)
    Q_PROPERTY(QString monitorName READ monitorName NOTIFY stateChanged)
    Q_PROPERTY(QVariantList monitors READ monitors NOTIFY stateChanged)
    Q_PROPERTY(bool darkMode READ darkMode NOTIFY stateChanged)
    Q_PROPERTY(QString localIp READ localIp NOTIFY stateChanged)
    Q_PROPERTY(QString networkType READ networkType NOTIFY stateChanged)
    Q_PROPERTY(bool wifiSupported READ wifiSupported NOTIFY wifiChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY wifiChanged)
    Q_PROPERTY(QVariantList wifiNetworks READ wifiNetworks NOTIFY wifiChanged)
    Q_PROPERTY(bool bluetoothSupported READ bluetoothSupported NOTIFY bluetoothChanged)
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled NOTIFY bluetoothChanged)
    Q_PROPERTY(QVariantList bluetoothDevices READ bluetoothDevices NOTIFY bluetoothChanged)

public:
    explicit SystemControlService(QObject* parent = nullptr);
    ~SystemControlService() override;

    bool brightnessSupported() const { return m_brightnessSupported; }
    int brightness() const { return m_brightness; }
    QString monitorName() const { return m_monitorName; }
    QVariantList monitors() const { return m_monitors; }
    bool darkMode() const { return m_darkMode; }
    QString localIp() const { return m_localIp; }
    QString networkType() const { return m_networkType; }
    bool wifiSupported() const { return m_wifiSupported; }
    bool wifiEnabled() const { return m_wifiEnabled; }
    QVariantList wifiNetworks() const { return m_wifiNetworks; }
    bool bluetoothSupported() const { return m_bluetoothSupported; }
    bool bluetoothEnabled() const { return m_bluetoothEnabled; }
    QVariantList bluetoothDevices() const { return m_bluetoothDevices; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshWifi();
    Q_INVOKABLE void toggleWifi();
    Q_INVOKABLE void connectWifi(const QString& ssid);
    Q_INVOKABLE void refreshBluetooth();
    Q_INVOKABLE void toggleBluetooth();
    Q_INVOKABLE void setBrightness(int percent);
    Q_INVOKABLE void setMonitorBrightness(int index, int percent);
    Q_INVOKABLE void setDisplayMode(const QString& mode);
    Q_INVOKABLE void toggleDarkMode();
    Q_INVOKABLE void openSettings(const QString& uri);
    Q_INVOKABLE void lockScreen();
    Q_INVOKABLE void sleepPc();
    Q_INVOKABLE void shutdownPc();
    Q_INVOKABLE void restartPc();
    Q_INVOKABLE void hibernatePc();
    Q_INVOKABLE void signOut();
    Q_INVOKABLE QString pickImageFile(const QString& title = QStringLiteral("Select Image"));

    bool nativeEventFilter(const QByteArray& eventType, void* message, qintptr* result) override;

signals:
    void stateChanged();
    void wifiChanged();
    void bluetoothChanged();
    void quickPanelToggleRequested();
    void spotlightToggleRequested();
    void clipboardToggleRequested();

private:
    void readBrightness();
    void readDarkMode();
    void readNetwork();
    void registerHotkeys();

    bool m_brightnessSupported = false;
    int m_brightness = 100;
    QString m_monitorName;
    QVariantList m_monitors;
    bool m_darkMode = true;
    QString m_localIp;
    QString m_networkType = QStringLiteral("Offline");
    bool m_wifiSupported = false;
    bool m_wifiEnabled = false;
    QVariantList m_wifiNetworks;
    bool m_bluetoothSupported = false;
    bool m_bluetoothEnabled = false;
    QVariantList m_bluetoothDevices;
    bool m_hotkeyRegistered = false;
    bool m_spotlightHotkeyRegistered = false;
    bool m_clipboardHotkeyRegistered = false;
    void* m_kbdHook = nullptr;
    void* m_hotkeyMsgHwnd = nullptr;
    QTimer m_hotkeyRetryTimer;
};
