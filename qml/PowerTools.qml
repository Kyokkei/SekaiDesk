import QtQuick
import Quickshell
import SekaiDesk

Item {
    id: powerToolsRoot
    visible: false

    required property var themeHub
    required property bool fullscreenActive

    signal quickPanelRequested()
    signal dismissQuickPanelRequested()

    Connections {
        target: SystemControl
        function onSpotlightToggleRequested() {
            if (launcherPhone.visible && !launcherPhone.isClipMode) {
                launcherPhone.closePhone()
                return
            }
            if ((Date.now() - themeHub.spotlightClosedAt) < 80)
                return
            launcherPhone.allowOverFullscreen = true
            powerToolsRoot.dismissQuickPanelRequested()
            themeHub.clipboardOpen = false
            themeHub.settingsOpen = false
            themeHub.launcherInitialQuery = ""
            if (themeHub.spotlightOpen)
                launcherPhone.applyInitialQuery("")
            else
                themeHub.spotlightOpen = true
        }

        function onClipboardToggleRequested() {
            if (powerToolsRoot.fullscreenActive)
                return
            if (launcherPhone.visible && launcherPhone.isClipMode) {
                launcherPhone.closePhone()
                return
            }
            if ((Date.now() - themeHub.spotlightClosedAt) < 80)
                return
            launcherPhone.allowOverFullscreen = false
            powerToolsRoot.dismissQuickPanelRequested()
            themeHub.clipboardOpen = false
            themeHub.settingsOpen = false
            themeHub.launcherInitialQuery = "clip"
            if (themeHub.spotlightOpen)
                launcherPhone.applyInitialQuery("clip")
            else
                themeHub.spotlightOpen = true
        }
    }

    Connections {
        target: themeHub
        function onClipboardOpenChanged() {
            if (!themeHub.clipboardOpen)
                return
            themeHub.clipboardOpen = false
            if (powerToolsRoot.fullscreenActive)
                return
            if (launcherPhone.visible && launcherPhone.isClipMode) {
                launcherPhone.closePhone()
            } else {
                launcherPhone.allowOverFullscreen = false
                powerToolsRoot.dismissQuickPanelRequested()
                themeHub.settingsOpen = false
                themeHub.launcherInitialQuery = "clip"
                if (themeHub.spotlightOpen)
                    launcherPhone.applyInitialQuery("clip")
                else
                    themeHub.spotlightOpen = true
            }
        }
    }

    LauncherPhone2D {
        id: launcherPhone
        themeHub: powerToolsRoot.themeHub
        fullscreenActive: powerToolsRoot.fullscreenActive
        onOpenQuickPanelRequested: powerToolsRoot.quickPanelRequested()
    }

    DropShelfBookshelf {
        id: dropShelfBookshelf
        themeHub: powerToolsRoot.themeHub
        fullscreenActive: powerToolsRoot.fullscreenActive
    }
}
