#pragma once
// QsWindow — compat layer for Quickshell windowing on Windows.
//
// Design rules (from the master blueprint, section 7.2 — SURVIVAL RULES):
//  - NEVER full-screen transparent overlay windows. Windows hug their content.
//  - Transparent regions inside the window must be cut with setMask()
//    (SetWindowRgn) so clicks pass through — alpha == 0 does NOT pass clicks.
//  - Click-through empty zones use WS_EX_TRANSPARENT via `clickThrough`.

#include <QObject>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegion>
#include <QVariant>

// ---------------------------------------------------------------------------
// MarginGroup: anchors.margins { left / top / right / bottom }
// ---------------------------------------------------------------------------
class MarginGroup : public QObject {
    Q_OBJECT
    Q_PROPERTY(int left READ left WRITE setLeft NOTIFY changed)
    Q_PROPERTY(int top READ top WRITE setTop NOTIFY changed)
    Q_PROPERTY(int right READ right WRITE setRight NOTIFY changed)
    Q_PROPERTY(int bottom READ bottom WRITE setBottom NOTIFY changed)

public:
    explicit MarginGroup(QObject* parent = nullptr);

    int left() const { return m_left; }
    void setLeft(int v) { if (m_left != v) { m_left = v; emit changed(); } }
    int top() const { return m_top; }
    void setTop(int v) { if (m_top != v) { m_top = v; emit changed(); } }
    int right() const { return m_right; }
    void setRight(int v) { if (m_right != v) { m_right = v; emit changed(); } }
    int bottom() const { return m_bottom; }
    void setBottom(int v) { if (m_bottom != v) { m_bottom = v; emit changed(); } }

signals:
    void changed();

private:
    int m_left = 0;
    int m_top = 0;
    int m_right = 0;
    int m_bottom = 0;
};

// ---------------------------------------------------------------------------
// WindowAnchors: which screen edges the panel sticks to.
// ---------------------------------------------------------------------------
class WindowAnchors : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool left READ left WRITE setLeft NOTIFY changed)
    Q_PROPERTY(bool top READ top WRITE setTop NOTIFY changed)
    Q_PROPERTY(bool right READ right WRITE setRight NOTIFY changed)
    Q_PROPERTY(bool bottom READ bottom WRITE setBottom NOTIFY changed)
    Q_PROPERTY(MarginGroup* margins READ margins CONSTANT)

public:
    explicit WindowAnchors(QObject* parent = nullptr);

    bool left() const { return m_left; }
    void setLeft(bool v) { if (m_left != v) { m_left = v; emit changed(); } }
    bool top() const { return m_top; }
    void setTop(bool v) { if (m_top != v) { m_top = v; emit changed(); } }
    bool right() const { return m_right; }
    void setRight(bool v) { if (m_right != v) { m_right = v; emit changed(); } }
    bool bottom() const { return m_bottom; }
    void setBottom(bool v) { if (m_bottom != v) { m_bottom = v; emit changed(); } }

    MarginGroup* margins() const { return m_margins; }

signals:
    void changed();

private:
    bool m_left = false;
    bool m_top = false;
    bool m_right = false;
    bool m_bottom = false;
    MarginGroup* m_margins;
};

// ---------------------------------------------------------------------------
// QsRegion: mask description. Either bound to an item (bounding rect mapped
// into the window) or an explicit list of rects { x, y, width, height }.
// Scaffold scope: bounding-box only; per-corner shaped masks (dock
// magnification wave) refine this in Phase 1b.
// ---------------------------------------------------------------------------
class QsRegion : public QObject {
    Q_OBJECT
    Q_PROPERTY(QQuickItem* item READ item WRITE setItem NOTIFY itemChanged)
    Q_PROPERTY(QVariantList regions READ regions WRITE setRegions NOTIFY regionsChanged)

public:
    explicit QsRegion(QObject* parent = nullptr);

    QQuickItem* item() const { return m_item; }
    void setItem(QQuickItem* item);

    QVariantList regions() const { return m_regions; }
    void setRegions(const QVariantList& regions);

    // Computes the region relative to the given window (scene coordinates).
    QRegion regionRelativeTo(const QQuickWindow* win) const;

signals:
    void itemChanged();
    void regionsChanged();

private:
    void handleItemChanged();

    QQuickItem* m_item = nullptr;
    QVariantList m_regions;
};

// ---------------------------------------------------------------------------
// PanelWindow: frameless, translucent, always-on-top app panel that hugs its
// content. Replaces Quickshell's Wayland layer-shell PanelWindow with plain
// Win32 semantics:
//  - frameless + topmost + tool window (hidden from taskbar / Alt+Tab)
//  - anchors to screen edges with margins
//  - mask (QRegion) cuts transparent areas so clicks fall through to the
//    desktop below (right-click desktop menu stays alive)
//  - clickThrough switches WS_EX_TRANSPARENT for pure overlay zones
// ---------------------------------------------------------------------------
class PanelWindow : public QQuickWindow {
    Q_OBJECT
    Q_PROPERTY(WindowAnchors* anchors READ anchors CONSTANT)
    Q_PROPERTY(int exclusiveZone READ exclusiveZone WRITE setExclusiveZone NOTIFY exclusiveZoneChanged)
    Q_PROPERTY(bool clickThrough READ clickThrough WRITE setClickThrough NOTIFY clickThroughChanged)
    Q_PROPERTY(QVariant mask READ maskProperty WRITE setMaskProperty NOTIFY maskChanged)
    Q_PROPERTY(bool reserveTopBar READ reserveTopBar WRITE setReserveTopBar NOTIFY reserveTopBarChanged)
    Q_PROPERTY(int reserveHeight READ reserveHeight WRITE setReserveHeight NOTIFY reserveHeightChanged)
    Q_PROPERTY(bool fullscreenActive READ fullscreenActive NOTIFY fullscreenActiveChanged)

public:
    explicit PanelWindow(QWindow* parent = nullptr);
    ~PanelWindow() override;

    WindowAnchors* anchors() const { return m_anchors; }

    int exclusiveZone() const { return m_exclusiveZone; }
    void setExclusiveZone(int zone) {
        if (m_exclusiveZone != zone) {
            m_exclusiveZone = zone;
            emit exclusiveZoneChanged();
        }
    }

    bool clickThrough() const { return m_clickThrough; }
    void setClickThrough(bool on);

    QVariant maskProperty() const { return m_mask; }
    void setMaskProperty(const QVariant& mask);

    bool reserveTopBar() const { return m_reserveTopBar; }
    void setReserveTopBar(bool on);

    int reserveHeight() const { return m_reserveHeight; }
    void setReserveHeight(int h);

    bool fullscreenActive() const { return m_fullscreenActive; }

    Q_INVOKABLE void recompute();
    Q_INVOKABLE bool isPointerOutsideAndPressed() const;

signals:
    void exclusiveZoneChanged();
    void clickThroughChanged();
    void maskChanged();
    void reserveTopBarChanged();
    void reserveHeightChanged();
    void fullscreenActiveChanged();
    void windowDeactivated();

protected:
    bool nativeEvent(const QByteArray& eventType, void* message, qintptr* result) override;

private:
    void recomputeGeometry();
    void applyClickThrough();
    void updateMask();
    void registerOrUpdateAppBar();
    void unregisterAppBar();

    WindowAnchors* m_anchors;
    int m_exclusiveZone = -1;
    bool m_clickThrough = false;
    bool m_geometryOwned = false;
    QVariant m_mask;
    QRegion m_lastMask;
    bool m_hasAppliedMask = false;
    bool m_reserveTopBar = false;
    int m_reserveHeight = 48;
    bool m_appBarRegistered = false;
    bool m_fullscreenActive = false;
    QMetaObject::Connection m_screenGeoConn;
};
