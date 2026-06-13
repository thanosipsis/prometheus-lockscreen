//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "theme" as PrometheusTheme

ShellRoot {
    id: shell

    PrometheusTheme.Theme { id: theme }

    readonly property string targetScreen: Quickshell.env("PROMETHEUS_LOCKSCREEN_TARGET_SCREEN") || ""
    readonly property bool targetAllScreens: targetScreen.length === 0 || targetScreen === "*"
    readonly property bool previewMode: Quickshell.env("QUICKSHELL_LOCKSCREEN_PREVIEW") === "1"
    readonly property string pamConfigDirectory: Quickshell.env("PROMETHEUS_LOCKSCREEN_PAM_DIR") || "/etc/pam.d"
    readonly property string pamConfig: Quickshell.env("PROMETHEUS_LOCKSCREEN_PAM_CONFIG") || "prometheus-lockscreen"
    readonly property string facePamConfig: Quickshell.env("PROMETHEUS_LOCKSCREEN_FACE_PAM_CONFIG") || "prometheus-lockscreen-face"
    readonly property string faceAuthTriggerFile: Quickshell.env("PROMETHEUS_LOCKSCREEN_FACE_TRIGGER_FILE") || ((Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/prometheus-lockscreen-face-trigger")
    readonly property bool faceAuthEnabled: envFlag("PROMETHEUS_LOCKSCREEN_FACE_AUTH", false)
    readonly property string lockController: Quickshell.env("PROMETHEUS_LOCKCTL") || "prometheus-lockctl"
    readonly property bool powerButtonsEnabled: envFlag("PROMETHEUS_LOCKSCREEN_POWER_BUTTONS", true)
    readonly property bool burnInProtectionEnabled: envFlag("PROMETHEUS_LOCKSCREEN_BURN_IN", true)
    readonly property int burnInShiftPixels: envInt("PROMETHEUS_LOCKSCREEN_BURN_IN_SHIFT_PIXELS", 4)
    readonly property int burnInShiftIntervalSeconds: envInt("PROMETHEUS_LOCKSCREEN_BURN_IN_INTERVAL_SECONDS", 45)
    readonly property int credentialInputHeight: 32
    readonly property int credentialPanelHeight: 88
    readonly property string authUser: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
    readonly property bool lockSecure: previewMode || lock.secure
    readonly property string fontFamily: theme.fontFamily
    readonly property string timeFontFamily: theme.titleFontFamily
    readonly property color bg: theme.lockBackground
    readonly property color ink: theme.prometheusInk
    readonly property color muted: theme.muted
    readonly property color line: theme.lockLine
    readonly property color panel: theme.lockPanel
    readonly property color panelSoft: theme.lockPanelSoft
    readonly property color danger: theme.danger
    readonly property int maxPasswordAttempts: 3
    readonly property int passwordCooldownSeconds: 60
    property string passwordText: ""
    property string pendingPassword: ""
    property string statusText: ""
    property string uptimeText: "--"
    property int passwordAttempts: 0
    property int cooldownRemaining: 0
    property bool authInProgress: false
    property bool powerInProgress: false
    property string activePowerCommand: ""
    property string activePowerLabel: ""
    property bool faceAuthInProgress: false
    property bool faceAuthTriggerInitialized: false
    property string lastFaceAuthTrigger: ""
    property bool unlocking: false
    property bool statusIsError: false
    readonly property bool passwordLocked: cooldownRemaining > 0
    property int burnInOffset: 0
    property bool burnInShiftUp: false

    function envFlag(name, fallback) {
        const value = (Quickshell.env(name) || "").toLowerCase();

        if (value === "1" || value === "true" || value === "yes" || value === "on") {
            return true;
        }

        if (value === "0" || value === "false" || value === "no" || value === "off") {
            return false;
        }

        return fallback;
    }

    function envInt(name, fallback) {
        const value = parseInt(Quickshell.env(name) || "", 10);
        return isNaN(value) ? fallback : value;
    }

    function clearSecrets() {
        passwordText = "";
        pendingPassword = "";
    }

    Component.onCompleted: {
        if (!previewMode) {
            lock.locked = true;
        }

        uptimeProcess.running = true;
        if (faceAuthEnabled) {
            faceTriggerProcess.running = true;
        }
    }

    // Successful auth should release the session lock immediately; no fade layer.
    function unlock() {
        if (unlocking) {
            return;
        }

        authInProgress = false;
        faceAuthInProgress = false;
        clearSecrets();
        unlocking = true;
        lock.locked = false;
        Qt.quit();
    }

    function resetLockIdleTimer() {
        if (previewMode) {
            return;
        }

        if (unlocking) {
            return;
        }
    }

    function submitPassword() {
        if (previewMode) {
            statusText = "Preview mode";
            statusIsError = false;
            return;
        }

        resetLockIdleTimer();

        if (passwordLocked) {
            statusText = "Too many attempts - wait " + cooldownRemaining + "s";
            statusIsError = true;
            return;
        }

        if (authInProgress || powerInProgress) {
            return;
        }

        if (passwordText.length === 0) {
            statusText = "Password required";
            statusIsError = true;
            return;
        }

        pendingPassword = passwordText;
        passwordText = "";
        authInProgress = true;
        statusText = "Checking password";
        statusIsError = false;
        pam.user = authUser;
        if (!pam.start()) {
            pendingPassword = "";
            authInProgress = false;
            statusText = "Authentication unavailable";
            statusIsError = true;
        }
    }

    function startFaceUnlock() {
        if (!faceAuthEnabled || previewMode || unlocking || passwordLocked || authInProgress || faceAuthInProgress || powerInProgress) {
            return;
        }

        resetLockIdleTimer();
        faceAuthInProgress = true;
        statusText = "Checking face";
        statusIsError = false;
        facePam.user = authUser;
        if (!facePam.start()) {
            faceAuthInProgress = false;
            statusText = "Face authentication unavailable";
            statusIsError = true;
        }
    }

    function requestFaceUnlockShortcut() {
        if (previewMode) {
            statusText = "Preview mode";
            statusIsError = false;
            return;
        }

        resetLockIdleTimer();

        if (!faceAuthEnabled) {
            statusText = "Face unlock unavailable";
            statusIsError = true;
            return;
        }

        if (passwordLocked) {
            statusText = "Too many attempts - wait " + cooldownRemaining + "s";
            statusIsError = true;
            return;
        }

        startFaceUnlock();
    }

    function registerFailedAttempt() {
        passwordAttempts = Math.min(passwordAttempts + 1, maxPasswordAttempts);
        const triesLeft = Math.max(maxPasswordAttempts - passwordAttempts, 0);

        if (triesLeft === 0) {
            cooldownRemaining = passwordCooldownSeconds;
            statusText = "Too many attempts - wait " + cooldownRemaining + "s";
            statusIsError = true;
            cooldownTimer.restart();
            return;
        }

        statusText = "Wrong password - " + triesLeft + " " + (triesLeft === 1 ? "try" : "tries") + " left";
        statusIsError = true;
    }

    function powerAction(action) {
        if (previewMode || powerInProgress) {
            return;
        }

        resetLockIdleTimer();

        clearSecrets();

        if (!lock.secure) {
            statusText = "Lock is still securing";
            statusIsError = true;
            return;
        }

        if (action === "Reboot") {
            activePowerCommand = "reboot";
            activePowerLabel = "Restart";
            statusText = "Restarting";
        } else if (action === "Sleep") {
            activePowerCommand = "suspend";
            activePowerLabel = "Sleep";
            statusText = "Sleeping";
        } else if (action === "Shutdown") {
            activePowerCommand = "poweroff";
            activePowerLabel = "Shutdown";
            statusText = "Shutting down";
        } else {
            return;
        }

        powerInProgress = true;
        statusIsError = false;
        Quickshell.execDetached([lockController, "power", activePowerCommand]);
        powerRecoveryTimer.restart();
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: uptimeProcess.running = true
    }

    Timer {
        interval: shell.burnInShiftIntervalSeconds * 1000
        running: shell.burnInProtectionEnabled
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            // Tiny alternating offset reduces static OLED wear without moving layout anchors.
            shell.burnInShiftUp = !shell.burnInShiftUp;
            shell.burnInOffset = shell.burnInShiftUp ? -shell.burnInShiftPixels : shell.burnInShiftPixels;
        }
    }

    Timer {
        id: cooldownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            shell.cooldownRemaining = Math.max(shell.cooldownRemaining - 1, 0);

            if (shell.cooldownRemaining > 0) {
                shell.statusText = "Too many attempts - wait " + shell.cooldownRemaining + "s";
                shell.statusIsError = true;
            } else {
                stop();
                shell.passwordAttempts = 0;
                shell.statusText = "";
                shell.statusIsError = false;
            }
        }
    }

    Timer {
        id: faceTriggerTimer
        interval: 1000
        running: shell.faceAuthEnabled && !shell.previewMode
        repeat: true
        onTriggered: {
            if (!faceTriggerProcess.running) {
                faceTriggerProcess.running = true;
            }
        }
    }

    Timer {
        id: powerRecoveryTimer
        interval: shell.activePowerCommand === "suspend" ? 12000 : 15000
        repeat: false
        onTriggered: {
            const command = shell.activePowerCommand;
            const label = shell.activePowerLabel || "Power action";

            shell.powerInProgress = false;
            shell.activePowerCommand = "";
            shell.activePowerLabel = "";

            if (command === "suspend") {
                shell.statusText = "";
                shell.statusIsError = false;
            } else {
                shell.statusText = label + " did not start";
                shell.statusIsError = true;
            }
        }
    }

    onBurnInProtectionEnabledChanged: {
        if (!burnInProtectionEnabled) {
            burnInOffset = 0;
            burnInShiftUp = false;
        }
    }

    Process {
        id: uptimeProcess
        command: ["bash", "-lc", "awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); if (d>0) printf \"%dd %02dh %02dm\", d, h, m; else printf \"%02dh %02dm\", h, m}' /proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: shell.uptimeText = this.text.trim()
        }
    }

    Process {
        id: faceTriggerProcess
        command: ["bash", "-lc", "cat " + JSON.stringify(shell.faceAuthTriggerFile) + " 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const token = this.text.trim();

                if (!shell.faceAuthTriggerInitialized) {
                    shell.faceAuthTriggerInitialized = true;
                    shell.lastFaceAuthTrigger = token;
                    return;
                }

                if (token.length > 0 && token !== shell.lastFaceAuthTrigger) {
                    shell.lastFaceAuthTrigger = token;
                    shell.startFaceUnlock();
                }
            }
        }
    }

    PamContext {
        id: pam
        configDirectory: shell.pamConfigDirectory
        config: shell.pamConfig
        user: shell.authUser

        onPamMessage: {
            if (responseRequired && shell.pendingPassword.length > 0) {
                respond(shell.pendingPassword);
                shell.pendingPassword = "";
            }
        }

        onCompleted: function(result) {
            shell.authInProgress = false;
            shell.pendingPassword = "";

            if (result === PamResult.Success) {
                shell.unlock();
            } else {
                shell.registerFailedAttempt();
            }
        }

        onError: {
            shell.authInProgress = false;
            shell.pendingPassword = "";
            shell.statusText = "Authentication unavailable";
            shell.statusIsError = true;
        }
    }

    PamContext {
        id: facePam
        configDirectory: shell.pamConfigDirectory
        config: shell.facePamConfig
        user: shell.authUser

        onCompleted: function(result) {
            shell.faceAuthInProgress = false;

            if (result === PamResult.Success) {
                shell.unlock();
            } else if (!shell.unlocking) {
                shell.statusText = "Face not recognized - enter password";
                shell.statusIsError = true;
            }
        }

        onError: {
            shell.faceAuthInProgress = false;
            shell.statusText = "Face authentication unavailable";
            shell.statusIsError = true;
        }
    }

    WlSessionLock {
        id: lock

        WlSessionLockSurface {
            id: root

            // Session-lock covers every monitor. With no target screen, the UI appears everywhere.
            readonly property bool showUi: shell.targetAllScreens || (screen !== null && screen.name === shell.targetScreen)

            color: "transparent"

            LockVisual {
                anchors.fill: parent
                showUi: root.showUi
                preview: false
            }
        }
    }

    PanelWindow {
        id: previewWindow
        visible: shell.previewMode
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "prometheus-lockscreen-preview"

        anchors {
            left: true
            top: true
            right: true
            bottom: true
        }

        LockVisual {
            anchors.fill: parent
            showUi: true
            preview: true
        }
    }

    component LockVisual: Item {
        id: surface

        required property bool showUi
        property bool preview: false
        property int focusAttempts: 0
        readonly property bool passwordShouldOwnFocus: showUi
            && !preview
            && !shell.unlocking
            && !shell.passwordLocked
            && !shell.powerInProgress
            && !shell.faceAuthInProgress
            && !rebootButton.activeFocus
            && !sleepButton.activeFocus
            && !shutdownButton.activeFocus
            && !enterButton.activeFocus

        anchors.fill: parent
        focus: true
            Keys.onPressed: function(event) {
                if (shell.unlocking) {
                    event.accepted = true;
                    return;
                }

                shell.resetLockIdleTimer();

                if (surface.handleFaceUnlockShortcut(event)) {
                    return;
                }

                if (event.key === Qt.Key_Escape) {
                    event.accepted = true;
                }
            }
            Component.onCompleted: {
                surface.requestPasswordFocus();
            }

            onShowUiChanged: requestPasswordFocus()
            onPasswordShouldOwnFocusChanged: requestPasswordFocus()

            function requestPasswordFocus() {
                if (!surface.passwordShouldOwnFocus) {
                    return;
                }

                surface.focusAttempts = 0;
                focusTimer.restart();
            }

            function handleFaceUnlockShortcut(event) {
                if (event.key !== Qt.Key_F1) {
                    return false;
                }

                shell.requestFaceUnlockShortcut();
                event.accepted = true;
                return true;
            }

            Timer {
                id: focusTimer
                interval: 100
                repeat: true
                onTriggered: {
                    if (!surface.passwordShouldOwnFocus) {
                        stop();
                        return;
                    }

                    surface.focusAttempts++;
                    surface.forceActiveFocus();
                    passwordInput.forceActiveFocus();

                    if (passwordInput.activeFocus || surface.focusAttempts >= 30) {
                        stop();
                    }
                }
            }

            Timer {
                id: focusMaintenanceTimer
                interval: 500
                running: surface.passwordShouldOwnFocus && !passwordInput.activeFocus
                repeat: true
                onTriggered: surface.requestPasswordFocus()
            }

            Rectangle {
                anchors.fill: parent
                color: shell.bg
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
                onPositionChanged: shell.resetLockIdleTimer()
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 24
                visible: surface.showUi
                color: "transparent"
                border.width: 2
                border.color: "#323c40"
                transform: Translate { y: shell.burnInOffset }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 30
                visible: surface.showUi
                color: "transparent"
                border.width: 1
                border.color: "#151d20"
                transform: Translate { y: shell.burnInOffset }
            }

            Rectangle {
                id: terminalPanel
                anchors.centerIn: parent
                visible: surface.showUi
                width: Math.min(780, parent.width - 96)
                height: 360
                color: "transparent"
                border.width: 0
                border.color: "transparent"
                transform: Translate { y: shell.burnInOffset }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    color: "transparent"
                    border.width: 0
                    border.color: "transparent"
                }

                Item {
                    id: contentArea

                    readonly property int clockInputGap: 16
                    readonly property int statusLineGap: 8
                    readonly property int statusLineHeight: 16

                    anchors.fill: parent
                    anchors.margins: 38

                    Item {
                        id: lockContent

                        anchors.centerIn: parent
                        width: parent.width
                        height: clockText.implicitHeight
                            + contentArea.clockInputGap
                            + shell.credentialPanelHeight
                            + contentArea.statusLineGap
                            + contentArea.statusLineHeight

                    Text {
                        id: clockText

                        anchors.top: parent.top
                        width: parent.width
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: shell.ink
                        horizontalAlignment: Text.AlignHCenter
                        font.family: shell.timeFontFamily
                        font.pixelSize: Math.max(30, Math.min(46, terminalPanel.width * 0.06))
                        font.weight: Font.Normal
                        renderType: Text.NativeRendering
                    }

                    Rectangle {
                        id: credentialPanel
                        anchors.top: clockText.bottom
                        anchors.topMargin: contentArea.clockInputGap
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(340, terminalPanel.width - 120)
                        height: shell.credentialPanelHeight
                        color: "#a0060909"
                        border.width: 1
                        border.color: "#263033"
                        radius: 4

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "User:"
                                    color: shell.muted
                                    font.family: shell.fontFamily
                                    font.pixelSize: 12
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: shell.authUser
                                    color: shell.ink
                                    font.family: shell.fontFamily
                                    font.pixelSize: 12
                                    renderType: Text.NativeRendering
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.minimumHeight: shell.credentialInputHeight
                                Layout.preferredHeight: shell.credentialInputHeight
                                Layout.maximumHeight: shell.credentialInputHeight
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: shell.credentialInputHeight
                                    Layout.preferredHeight: shell.credentialInputHeight
                                    Layout.maximumHeight: shell.credentialInputHeight
                                    radius: 3
                                    color: shell.panelSoft
                                    border.width: 1
                                    border.color: passwordInput.activeFocus ? shell.ink : "#263033"

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: passwordInput.text.length === 0 && !passwordInput.activeFocus && !surface.preview
                                        text: "Password"
                                        color: "#566263"
                                        font.family: shell.fontFamily
                                        font.pixelSize: 12
                                        renderType: Text.NativeRendering
                                    }

                                    TextInput {
                                        id: passwordInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        activeFocusOnTab: true
                                        enabled: !surface.preview && !shell.passwordLocked && !shell.powerInProgress
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: surface.preview ? "xxxxxxxxxx" : shell.passwordText
                                        color: shell.ink
                                        selectionColor: "#405052"
                                        selectedTextColor: shell.ink
                                        echoMode: TextInput.Password
                                        passwordCharacter: "*"
                                        font.family: shell.fontFamily
                                        font.pixelSize: 12
                                        font.preferShaping: false
                                        font.features: { "liga": 0, "calt": 0 }
                                        font.preferTypoLineMetrics: true
                                        clip: true
                                        onTextChanged: {
                                            if (surface.preview) {
                                                return;
                                            }

                                            shell.passwordText = text;
                                            shell.resetLockIdleTimer();
                                        }
                                        Keys.onReturnPressed: shell.submitPassword()
                                        Keys.onEnterPressed: shell.submitPassword()
                                        Keys.onPressed: function(event) {
                                            surface.handleFaceUnlockShortcut(event);
                                        }
                                    }
                                }

                                TerminalButton {
                                    id: enterButton
                                    Layout.preferredWidth: 72
                                    Layout.minimumHeight: shell.credentialInputHeight
                                    Layout.preferredHeight: shell.credentialInputHeight
                                    Layout.maximumHeight: shell.credentialInputHeight
                                    label: "ENTER"
                                    primary: true
                                    buttonEnabled: surface.preview || (!shell.passwordLocked && !shell.authInProgress && !shell.powerInProgress && shell.passwordText.length > 0)
                                    onClicked: shell.submitPassword()
                                }
                            }
                        }
                    }

                    Text {
                        id: statusLine
                        anchors.top: credentialPanel.bottom
                        anchors.topMargin: contentArea.statusLineGap
                        anchors.horizontalCenter: credentialPanel.horizontalCenter
                        width: credentialPanel.width
                        height: contentArea.statusLineHeight
                        visible: surface.showUi && shell.statusText.length > 0
                        text: ":: " + shell.statusText
                        color: shell.statusIsError ? shell.danger : shell.muted
                        horizontalAlignment: Text.AlignHCenter
                        font.family: shell.fontFamily
                        font.pixelSize: 11
                        renderType: Text.NativeRendering
                    }
                    }
                }
            }

            RowLayout {
                id: footerHelp
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 48
                anchors.bottomMargin: 34
                visible: surface.showUi && shell.powerButtonsEnabled
                spacing: 18
                transform: Translate { y: shell.burnInOffset }

                Text {
                    text: "Tab Focus"
                    color: shell.muted
                    font.family: shell.fontFamily
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                }

                Text {
                    text: "F1 Face unlock"
                    color: shell.muted
                    font.family: shell.fontFamily
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                }

            }

            RowLayout {
                id: footerPower
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 34
                visible: surface.showUi
                spacing: 18
                transform: Translate { y: shell.burnInOffset }

                TerminalButton {
                    id: rebootButton
                    Layout.preferredWidth: 82
                    Layout.preferredHeight: 28
                    label: "REBOOT"
                    buttonEnabled: !shell.powerInProgress && shell.lockSecure
                    onClicked: shell.powerAction("Reboot")
                }

                TerminalButton {
                    id: sleepButton
                    Layout.preferredWidth: 74
                    Layout.preferredHeight: 28
                    label: "SLEEP"
                    buttonEnabled: !shell.powerInProgress && shell.lockSecure
                    onClicked: shell.powerAction("Sleep")
                }

                TerminalButton {
                    id: shutdownButton
                    Layout.preferredWidth: 98
                    Layout.preferredHeight: 28
                    label: "SHUTDOWN"
                    danger: true
                    buttonEnabled: !shell.powerInProgress && shell.lockSecure
                    onClicked: shell.powerAction("Shutdown")
                }
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 48
                anchors.bottomMargin: 42
                visible: surface.showUi
                text: "Uptime " + shell.uptimeText
                color: shell.muted
                font.family: shell.fontFamily
                font.pixelSize: 11
                renderType: Text.NativeRendering
                transform: Translate { y: shell.burnInOffset }
            }
        }

    component TerminalButton: Rectangle {
        id: button

        signal clicked()

        required property string label
        property bool primary: false
        property bool danger: false

        property bool buttonEnabled: true

        enabled: buttonEnabled
        activeFocusOnTab: buttonEnabled
        radius: 3
        opacity: buttonEnabled ? 1.0 : 0.42
        color: !buttonEnabled
            ? (danger ? "#150808" : primary ? "#111819" : "#050909")
            : mouseArea.pressed
            ? (danger ? "#3d1717" : primary ? "#d6dfdc" : "#172123")
            : mouseArea.containsMouse
                ? (danger ? "#2c1111" : primary ? "#b8c3c0" : "#10191b")
                : (danger ? "#1e0b0b" : primary ? "#1a2426" : "#070d0e")
        border.width: 1
        border.color: !buttonEnabled ? "#20292b" : activeFocus ? shell.ink : danger ? "#7b3a3a" : "#334044"

        Keys.onReturnPressed: {
            if (buttonEnabled) button.clicked();
        }
        Keys.onEnterPressed: {
            if (buttonEnabled) button.clicked();
        }
        Keys.onSpacePressed: {
            if (buttonEnabled) button.clicked();
        }

        Text {
            anchors.centerIn: parent
            text: button.label
            color: button.primary && button.buttonEnabled && (mouseArea.containsMouse || mouseArea.pressed) ? "#030606" : shell.ink
            font.family: shell.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            enabled: button.buttonEnabled
            hoverEnabled: button.buttonEnabled
            cursorShape: button.buttonEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (button.buttonEnabled) button.clicked()
        }
    }
}
