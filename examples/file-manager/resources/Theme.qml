pragma Singleton
import QtQuick

QtObject {
    property bool darkMode: false

    // Backgrounds
    readonly property color background:        darkMode ? "#1E293B" : "#FFFFFF"
    readonly property color sidebarBackground: darkMode ? "#162032" : "#F8FAFC"

    // Surfaces & interactive
    readonly property color surfaceHover:  darkMode ? "#334155" : "#F1F5F9"
    readonly property color surfaceActive: darkMode ? "#334155" : "#E2E8F0"
    readonly property color border:        darkMode ? "#334155" : "#E2E8F0"

    // Text
    readonly property color textPrimary:   darkMode ? "#E2E8F0" : "#334155"
    readonly property color textSecondary: darkMode ? "#94A3B8" : "#64748B"
    readonly property color textTertiary:  darkMode ? "#64748B" : "#94A3B8"
    readonly property color textHeading:   darkMode ? "#F8FAFC" : "#0F172A"
    readonly property color textSeparator: darkMode ? "#475569" : "#CBD5E1"

    // Animation
    readonly property int animDuration:      200   // theme color transitions
    readonly property int animHoverDuration: 150   // hover highlight
    readonly property int animViewDuration:  250   // content fade/slide on navigation
    readonly property real animViewOffset:   8     // slide distance (px)
}
