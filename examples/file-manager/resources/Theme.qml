pragma Singleton
import QtQuick

QtObject {
    // Theme mode: "light", "dark", or "system"
    property string themeMode: "system"

    // System dark mode detection (Qt 6.5+)
    readonly property bool systemDark: Qt.styleHints.colorScheme === Qt.Dark

    // Effective dark mode: derived from themeMode
    readonly property bool darkMode: themeMode === "dark" ? true
                                   : themeMode === "light" ? false
                                   : systemDark

    // Backgrounds
    readonly property color background:        darkMode ? "#1E293B" : "#FFFFFF"
    readonly property color sidebarBackground: "transparent"

    // Surfaces & interactive
    readonly property color surfaceHover:      darkMode ? "#334155" : "#F1F5F9"
    readonly property color surfaceHoverOff:   Qt.alpha(surfaceHover, 0)
    readonly property color surfaceActive:     darkMode ? Qt.rgba(0.2, 0.25, 0.33, 0.3) : Qt.rgba(0, 0, 0, 0.1)
    readonly property color surfaceActiveOff:  Qt.alpha(surfaceActive, 0)
    readonly property color border:            darkMode ? "#334155" : "#E2E8F0"

    // Text
    readonly property color textPrimary:   darkMode ? "#E2E8F0" : "#334155"
    readonly property color textSecondary: darkMode ? "#94A3B8" : "#64748B"
    readonly property color textTertiary:  darkMode ? "#64748B" : "#94A3B8"
    readonly property color textHeading:   darkMode ? "#F8FAFC" : "#0F172A"
    readonly property color textSeparator: darkMode ? "#475569" : "#CBD5E1"

    // Animation
    readonly property int animDuration:      200   // theme color transitions
    readonly property int animHoverDuration: 100   // hover highlight
    readonly property int animViewDuration:  250   // content fade/slide on navigation
    readonly property real animViewOffset:   8     // slide distance (px)
    readonly property int animItemDuration:  200   // add/remove/displaced item transitions
    readonly property real animItemScale:    0.8   // scale-from for add, scale-to for remove
}
