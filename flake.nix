{
  description = "JVM + Qt/QML Integration Research";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Platform detection
        isDarwin = pkgs.stdenv.isDarwin;
        isLinux = pkgs.stdenv.isLinux;

        # Qt6 with QML modules we need
        qt6Packages = with pkgs.qt6; [
          qtbase
          qtdeclarative # QML engine
          # qtwayland        # Uncomment if needed on Linux/Wayland
        ];

        # Platform-specific dependencies
        platformDeps =
          if isDarwin then
            [
              # macOS frameworks - Qt already bundles necessary frameworks
              # No additional frameworks needed for basic Qt apps
            ]
          else
            [
              # Linux X11/OpenGL dependencies
              pkgs.xorg.libX11
              pkgs.xorg.libXcursor
              pkgs.xorg.libXrandr
              pkgs.xorg.libXi
              pkgs.libGL
              pkgs.libxkbcommon
            ];

        # Common build tools
        buildTools = with pkgs; [
          cmake
          ninja
          pkg-config
          gnumake
        ];

        # Development utilities
        devTools = with pkgs; [
          git
          ripgrep # Fast code search
          jq # JSON processing (for JNI configs)
          clojure-lsp # Clojure language server
          babashka # Task runner for Clojure
        ];

        # Base JVM setup (Temurin for development)
        jvmBase = with pkgs; [
          temurin-bin-21
          clojure
        ];

        # GraalVM setup (for native-image experiments)
        jvmGraalVM = with pkgs; [
          graalvmPackages.graalvm-ce
          clojure
        ];

        # Common environment variables
        commonEnv = {
          # Help CMake find Qt
          CMAKE_PREFIX_PATH = "${pkgs.qt6.qtbase}:${pkgs.qt6.qtdeclarative}";

          # QML import paths
          QML2_IMPORT_PATH = "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml";

          # Qt platform plugin path
          QT_QPA_PLATFORM_PLUGIN_PATH = "${pkgs.qt6.qtbase}/lib/qt-6/plugins/platforms";
        };

        # Platform-specific Qt settings
        qtPlatformHook =
          if isDarwin then
            ''
              export QT_QPA_PLATFORM=cocoa
            ''
          else
            ''
              export QT_QPA_PLATFORM=xcb
            '';

        # Common shell hook content
        mkShellHook = jdk: ''
          ${qtPlatformHook}

          # JNI headers location
          export JAVA_HOME="${jdk}"
          export JNI_INCLUDE_PATH="$JAVA_HOME/include"

          # Platform info
          PLATFORM="${if isDarwin then "macOS (Darwin)" else "Linux"}"

          echo "┌────────────────────────────────────────────────────────────┐"
          echo "│       JVM + Qt/QML Integration Environment                 │"
          echo "├────────────────────────────────────────────────────────────┤"
          printf "│  %-58s│\n" "Platform: $PLATFORM"
          printf "│  %-58s│\n" "Qt6:      $(qmake6 --version 2>/dev/null | grep -oP 'Qt version \K[0-9.]+' || echo 'available')"
          printf "│  %-58s│\n" "JDK:      $(java --version 2>&1 | head -1)"
          printf "│  %-58s│\n" "Clojure:  $(clojure --version 2>&1 | head -1)"
          echo "└────────────────────────────────────────────────────────────┘"
          echo ""
          bb tasks 2>/dev/null || echo "  Run 'bb tasks' to see available tasks"
          echo ""
        '';

      in
      {
        # Default shell: Temurin JDK for regular development
        devShells.default = pkgs.mkShell (
          {
            name = "jvm-qt-research";

            buildInputs = qt6Packages ++ platformDeps ++ buildTools ++ devTools ++ jvmBase;

            shellHook = mkShellHook pkgs.temurin-bin-21;
          }
          // commonEnv
        );

        # GraalVM shell: for native-image experiments
        devShells.graalvm = pkgs.mkShell (
          {
            name = "jvm-qt-research-graalvm";

            buildInputs = qt6Packages ++ platformDeps ++ buildTools ++ devTools ++ jvmGraalVM;

            shellHook = mkShellHook pkgs.graalvmPackages.graalvm-ce + ''
              echo "GraalVM native-image: $(native-image --version 2>&1 | head -1 || echo 'run: gu install native-image')"
              echo ""
            '';
          }
          // commonEnv
        );
      }
    );
}
