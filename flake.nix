{
  description = "JVM + Qt/QML Integration Research";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nixgl,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        # Platform detection (before pkgs, so we can conditionally apply overlays)
        isLinux = builtins.match ".*-linux" system != null;
        isDarwin = builtins.match ".*-darwin" system != null;

        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
            "graalvm-oracle"
            "nvidia-x11"
            "nvidia"
          ];
          overlays = if isLinux then [ nixgl.overlay ] else [];
        };

        # Qt6 with QML modules we need
        qt6Packages = with pkgs.qt6; [
          qtbase
          qtdeclarative # QML engine
          qtsvg # SVG support for Image elements
          qt5compat # FastBlur, GraphicalEffects
        ] ++ pkgs.lib.optionals isLinux [ pkgs.qt6.qtwayland ];

        # Platform-specific dependencies
        platformDeps =
          if isDarwin then
            [
              # macOS frameworks - Qt already bundles necessary frameworks
              # No additional frameworks needed for basic Qt apps
            ]
          else
            [
              # Linux Wayland + X11/OpenGL dependencies
              pkgs.wayland
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
          jq # JSON processing
          clojure-lsp # Clojure language server
          babashka # Task runner for Clojure
          qt6.qtdeclarative # qmlformat, qmllint, qmlls
        ];

        # JVM setup: GraalVM 25 (Panama FFM support)
        graalvm25 = pkgs.graalvmPackages.graalvm-oracle_25;
        jvmBase = [
          graalvm25
          (pkgs.clojure.override { jdk = graalvm25; })
        ];

        # Common environment variables
        waylandPaths = if isLinux then ":${pkgs.qt6.qtwayland}" else "";
        waylandPluginPaths = if isLinux then ":${pkgs.qt6.qtwayland}/lib/qt-6/plugins" else "";

        commonEnv = {
          # Help CMake find Qt
          CMAKE_PREFIX_PATH = "${pkgs.qt6.qtbase}:${pkgs.qt6.qtdeclarative}:${pkgs.qt6.qtsvg}:${pkgs.qt6.qt5compat}${waylandPaths}";

          # QML import paths
          QML2_IMPORT_PATH = "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml:${pkgs.qt6.qt5compat}/lib/qt-6/qml";

          # Qt plugin paths (platform + image format plugins like SVG)
          QT_PLUGIN_PATH = "${pkgs.qt6.qtbase}/lib/qt-6/plugins:${pkgs.qt6.qtsvg}/lib/qt-6/plugins${waylandPluginPaths}";
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
              export QT_QPA_PLATFORM="wayland;xcb"

              # GPU acceleration via nixGL — extract its env vars into our shell
              if command -v nixGL &> /dev/null; then
                while IFS='=' read -r key value; do
                  case "$key" in
                    LD_LIBRARY_PATH|__EGL_VENDOR_LIBRARY_FILENAMES|__EGL_VENDOR_LIBRARY_DIRS|LIBGL_DRIVERS_PATH|__GLX_VENDOR_LIBRARY_NAME)
                      export "$key=$value"
                      ;;
                  esac
                done < <(nixGL env 2>/dev/null)
              fi
            '';

        # Common shell hook content
        mkShellHook = jdk: ''
          ${qtPlatformHook}

          export JAVA_HOME="${jdk}"

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
          if [ -n "$IN_NIX_SHELL" ] && [ "$SHELL_NAME" != "bash" ] && [[ $- == *i* ]]; then
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

            buildInputs = qt6Packages ++ platformDeps ++ buildTools ++ devTools ++ jvmBase
              ++ pkgs.lib.optionals isLinux [ pkgs.nixgl.auto.nixGLDefault ];

            shellHook = mkShellHook graalvm25;
          }
          // commonEnv
        );

      }
    );
}
