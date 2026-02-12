(ns cuirq.macos.window
  "macOS-specific window APIs: titlebar, vibrancy, app name."
  (:import [qml PanamaBridge]))

(defn set-app-name!
  "Set the application name shown in the macOS menu bar."
  [name]
  (PanamaBridge/setAppName name))

(defn hide-titlebar!
  "Hide the native titlebar for a seamless window look.
   Applies fullSizeContentView, transparent titlebar, hidden title,
   and exposes titlebar height to QML for layout offset."
  []
  (PanamaBridge/hideTitlebar))

(defn enable-sidebar-vibrancy!
  "Enable sidebar vibrancy effect (NSVisualEffectView).
   Width is the sidebar width in pixels."
  [width]
  (PanamaBridge/enableSidebarVibrancy (int width)))

(defn enable-toolbar-vibrancy!
  "Enable toolbar vibrancy effect (NSVisualEffectView with HeaderView material).
   sidebarWidth is the x offset, toolbarHeight is the height."
  [sidebar-width toolbar-height]
  (PanamaBridge/enableToolbarVibrancy (int sidebar-width) (int toolbar-height)))

(defn set-vibrancy-appearance!
  "Set sidebar vibrancy appearance. Mode: \"light\", \"dark\", or \"system\"."
  [mode]
  (PanamaBridge/setVibrancyAppearance (clojure.core/name mode)))

(defn set-vibrancy-always-active!
  "Keep vibrancy active even when window loses focus. Default: false."
  [always]
  (PanamaBridge/setVibrancyAlwaysActive (boolean always)))
