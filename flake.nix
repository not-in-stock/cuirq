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

          # Setup isolated shell history for this project
          PROJECT_HISTORY_DIR="$PWD/.history"
          mkdir -p "$PROJECT_HISTORY_DIR"

          # Detect current active shell (from parent process)
          if [ -z "''${CUIRQ_USER_SHELL:-}" ]; then
            # Get the parent process's shell
            # This detects the shell you're currently using, not system default
            PARENT_SHELL=$(ps -p $PPID -o comm= 2>/dev/null | sed 's/^-//')

            # Try to find the full path to this shell
            if [ -n "$PARENT_SHELL" ]; then
              # Check if parent shell is a known shell
              case "$PARENT_SHELL" in
                fish|zsh|bash)
                  USER_SHELL=$(command -v "$PARENT_SHELL" 2>/dev/null)
                  ;;
                *)
                  # If parent is not a shell, try to detect from system
                  if command -v dscl >/dev/null 2>&1; then
                    # macOS: use dscl
                    USER_SHELL=$(dscl . -read ~/ UserShell | awk '{print $2}')
                  elif [ -f /etc/passwd ]; then
                    # Linux: use /etc/passwd
                    USER_SHELL=$(getent passwd "$USER" | cut -d: -f7)
                  fi
                  ;;
              esac
            fi

            # Final fallback if detection failed
            if [ -z "$USER_SHELL" ] || [ ! -x "$USER_SHELL" ]; then
              USER_SHELL="''${SHELL:-/bin/bash}"
            fi
          else
            # User explicitly set their shell preference
            USER_SHELL="$CUIRQ_USER_SHELL"
          fi

          SHELL_NAME=$(basename "$USER_SHELL")

          case "$SHELL_NAME" in
            zsh)
              # Use project-local history for zsh
              export HISTFILE="$PROJECT_HISTORY_DIR/zsh_history"
              echo " Using project-local zsh history: $HISTFILE"
              ;;
            fish)
              # Use project-local history for fish
              # Fish stores history in XDG_DATA_HOME, so we override it
              export XDG_DATA_HOME="$PROJECT_HISTORY_DIR/fish"
              mkdir -p "$XDG_DATA_HOME/fish"
              echo " Using project-local fish history in: $XDG_DATA_HOME/fish"
              ;;
            bash)
              # Use project-local history for bash
              export HISTFILE="$PROJECT_HISTORY_DIR/bash_history"
              echo " Using project-local bash history: $HISTFILE"
              ;;
          esac

          # Launch user's shell with all their configs
          # Note: This replaces the current bash process with user's shell
          # Your shell configs (~/.zshrc, ~/.config/fish/config.fish, etc) will be loaded
          # Exit the shell to return to the original environment
          if [ -n "$IN_NIX_SHELL" ] && [ "$SHELL_NAME" != "bash" ]; then
            echo "Launching $SHELL_NAME..."
            echo ""
            exec "$USER_SHELL"
          fi
        '';

      in
      {
        # Default shell: JDK for regular development
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
