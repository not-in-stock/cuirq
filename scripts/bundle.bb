(ns bundle
  "Create a self-contained macOS .app bundle using macdeployqt."
  (:require [babashka.fs :as fs]
            [babashka.process :as p]
            [clojure.string :as str]))

(defn- otool-nix-deps
  "Return set of /nix/store/... dylib paths referenced by `path`."
  [path]
  (let [out (:out (deref (p/process {:out :string :err :string} "otool" "-L" (str path))))]
    (->> (str/split-lines out)
         (map str/trim)
         (keep #(when (str/starts-with? % "/nix/store/")
                  (let [path (first (str/split % #"\s+"))]
                    (if (str/ends-with? path ":")
                      (subs path 0 (dec (count path)))
                      path))))
         set)))

(defn- nix-store-path
  "Extract /nix/store/<hash>-<name> prefix from a full nix path."
  [nix-path]
  (let [parts (str/split nix-path #"/")]
    (str "/" (str/join "/" (take 4 parts)))))

(defn- find-nix-package
  "Find a nix package store path by scanning otool deps of the given binary
   for a path containing `package-name`."
  [binary package-name]
  (some->> (otool-nix-deps binary)
           (filter #(str/includes? % package-name))
           first
           nix-store-path))

(defn- rpath-ref
  "Given a nix dep path, return the @rpath reference to use.
   Framework: @rpath/QtCore.framework/Versions/A/QtCore
   Dylib:     @rpath/libfoo.dylib"
  [nix-path]
  (if (str/includes? nix-path ".framework/")
    (let [idx (str/index-of nix-path ".framework/")
          before (subs nix-path 0 idx)
          fw-basename (fs/file-name before)
          after (subs nix-path (+ idx (count ".framework/")))]
      (str "@rpath/" fw-basename ".framework/" after))
    (str "@rpath/" (fs/file-name nix-path))))

(defn- fix-nix-refs!
  "Rewrite all /nix/store references in `path` to @rpath/... form."
  [path]
  (let [deps (otool-nix-deps (str path))]
    (doseq [dep deps]
      (p/shell "install_name_tool" "-change" dep (rpath-ref dep) (str path))))
  ;; Fix install name (id)
  (let [fname (str (fs/file-name path))
        path-str (str path)
        id (if (str/includes? path-str ".framework/")
             (let [idx (str/index-of path-str ".framework/")
                   before (subs path-str 0 idx)
                   fw-basename (fs/file-name before)
                   after (subs path-str (+ idx (count ".framework/")))]
               (str "@rpath/" fw-basename ".framework/" after))
             (str "@rpath/" fname))]
    (p/shell "install_name_tool" "-id" id (str path))))

(defn- fix-remaining-nix-refs!
  "Fix nix refs in any dylibs/frameworks that macdeployqt missed.
   `dir` is the directory to scan, `contents-dir` is the Contents/ directory
   (used to compute correct rpath depth to Contents/Frameworks)."
  [dir contents-dir]
  ;; Plain dylibs
  (doseq [dylib (fs/glob dir "**/*.dylib")]
    (let [deps (otool-nix-deps (str dylib))]
      (when (seq deps)
        (fix-nix-refs! (str dylib))
        ;; Compute depth from dylib to Contents/, then add /Frameworks
        (let [rel (fs/relativize contents-dir dylib)
              depth (count (fs/components rel))
              up-segments (str/join "/" (repeat depth ".."))
              rpath (str "@loader_path/" up-segments "/Frameworks")]
          (try
            (p/shell "install_name_tool" "-add_rpath" rpath (str dylib))
            (catch Exception _ nil))))))
  ;; Framework binaries
  (doseq [fw-bin (fs/glob dir "**/*.framework/Versions/A/*")]
    (when (and (fs/regular-file? fw-bin)
              (not (str/ends-with? (str fw-bin) ".prl")))
      (let [deps (otool-nix-deps (str fw-bin))]
        (when (seq deps)
          (fix-nix-refs! (str fw-bin))
          (let [rel (fs/relativize contents-dir fw-bin)
                depth (count (fs/components rel))
                up-segments (str/join "/" (repeat depth ".."))
                rpath (str "@loader_path/" up-segments "/Frameworks")]
            (try
              (p/shell "install_name_tool" "-add_rpath" rpath (str fw-bin))
              (catch Exception _ nil))))))))

(defn bundle!
  "Create a macOS .app bundle for the given example."
  [example]
  (let [project-root (System/getProperty "user.dir")
        app-name     (str "Cuirq"
                          (->> (str/split example #"-")
                               (map str/capitalize)
                               (str/join)))
        native-bin   (str project-root "/build/native/cuirq-" example)
        bridge-lib   (str project-root "/build/lib/libqmlbridge.dylib")
        bundle-dir   (str project-root "/build/" app-name ".app")
        contents-dir (str bundle-dir "/Contents")
        macos-dir    (str contents-dir "/MacOS")
        fw-dir       (str contents-dir "/Frameworks")
        res-dir      (str contents-dir "/Resources")
        plugins-dir  (str contents-dir "/PlugIns")
        qml-dir      (str res-dir "/qml")]

    ;; 1. Validate inputs
    (when-not (fs/exists? native-bin)
      (println (str "Error: Native binary not found: " native-bin))
      (println "Run 'bb aot " example " && bb native " example "' first.")
      (System/exit 1))
    (when-not (fs/exists? bridge-lib)
      (println "Error: libqmlbridge.dylib not found. Run 'bb build' first.")
      (System/exit 1))

    ;; 2. Clean previous bundle
    (when (fs/exists? bundle-dir)
      (p/shell "chmod" "-R" "u+w" bundle-dir)
      (fs/delete-tree bundle-dir))

    (println (str "Creating " app-name ".app ..."))
    (println "")

    ;; 3. Create minimal .app structure for macdeployqt
    (doseq [d [macos-dir fw-dir]]
      (fs/create-dirs d))

    ;; Copy native binary
    (println (str "  Binary: cuirq-" example))
    (fs/copy native-bin (str macos-dir "/cuirq-" example) {:replace-existing true})
    (p/shell "chmod" "+x" (str macos-dir "/cuirq-" example))

    ;; Copy libqmlbridge.dylib into Frameworks
    (println "  Bridge: libqmlbridge.dylib")
    (fs/copy bridge-lib (str fw-dir "/libqmlbridge.dylib") {:replace-existing true})

    ;; Discover nix package paths for supplementation
    (let [qtsvg-dir     (or (find-nix-package bridge-lib "qtsvg")
                            (some-> (first (fs/glob "/nix/store" "*-qtsvg-*/lib/qt-6/plugins"))
                                    str nix-store-path))
          qtdecl-dir    (find-nix-package bridge-lib "qtdeclarative")
          qt5compat-dir (or (find-nix-package bridge-lib "qt5compat")
                            (some-> (first (fs/glob "/nix/store" "*-qt5compat-*/lib/qt-6/qml/Qt5Compat"))
                                    str nix-store-path))]

      ;; Generate Info.plist — use native binary name so macdeployqt finds it
      (let [bundle-id  (str "com.cuirq." (str/replace example "-" ""))
            make-plist (fn [executable]
                         (str "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                              "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
                              "<plist version=\"1.0\">\n"
                              "<dict>\n"
                              "    <key>CFBundleExecutable</key>\n"
                              "    <string>" executable "</string>\n"
                              "    <key>CFBundleIdentifier</key>\n"
                              "    <string>" bundle-id "</string>\n"
                              "    <key>CFBundleName</key>\n"
                              "    <string>" app-name "</string>\n"
                              "    <key>CFBundleDisplayName</key>\n"
                              "    <string>" app-name "</string>\n"
                              "    <key>CFBundlePackageType</key>\n"
                              "    <string>APPL</string>\n"
                              "    <key>CFBundleVersion</key>\n"
                              "    <string>0.1.0</string>\n"
                              "    <key>CFBundleShortVersionString</key>\n"
                              "    <string>0.1.0</string>\n"
                              "    <key>NSHighResolutionCapable</key>\n"
                              "    <true/>\n"
                              "    <key>NSSupportsAutomaticGraphicsSwitching</key>\n"
                              "    <true/>\n"
                              "</dict>\n"
                              "</plist>\n"))]
        (spit (str contents-dir "/Info.plist") (make-plist (str "cuirq-" example)))

        ;; 4. Run macdeployqt — handles frameworks, dylibs, qtbase plugins, rpaths, qt.conf
        ;; Note: -qmldir requires qmlimportscanner which nix ships in a separate package
        ;; with a hardcoded lookup path, so QML deployment is handled manually below.
        (println "")
        (println "Running macdeployqt...")
        (let [result (p/shell {:continue true}
                              "macdeployqt" bundle-dir
                              (str "-executable=" fw-dir "/libqmlbridge.dylib")
                              "-no-strip"
                              "-verbose=1")]
          (when-not (zero? (:exit result))
            (println "Warning: macdeployqt exited with non-zero status, continuing...")))

        ;; Update Info.plist to use "launch" as the executable
        (spit (str contents-dir "/Info.plist") (make-plist "launch")))

      ;; 5. Make everything writable (nix copies are read-only)
      (p/shell "chmod" "-R" "u+w" bundle-dir)

      ;; 6. Supplement — only copy what macdeployqt missed
      (println "")
      (println "Checking for missing components...")

      ;; QtSvg plugins (macdeployqt may have found them via -libpath)
      (when qtsvg-dir
        (let [svg-src  (str qtsvg-dir "/lib/qt-6/plugins/imageformats/libqsvg.dylib")
              icon-src (str qtsvg-dir "/lib/qt-6/plugins/iconengines/libqsvgicon.dylib")]
          (when (and (fs/exists? svg-src)
                     (not (fs/exists? (str plugins-dir "/imageformats/libqsvg.dylib"))))
            (fs/create-dirs (str plugins-dir "/imageformats"))
            (println "  Supplementing: imageformats/libqsvg.dylib")
            (fs/copy svg-src (str plugins-dir "/imageformats/libqsvg.dylib") {:replace-existing true}))
          (when (and (fs/exists? icon-src)
                     (not (fs/exists? (str plugins-dir "/iconengines/libqsvgicon.dylib"))))
            (fs/create-dirs (str plugins-dir "/iconengines"))
            (println "  Supplementing: iconengines/libqsvgicon.dylib")
            (fs/copy icon-src (str plugins-dir "/iconengines/libqsvgicon.dylib") {:replace-existing true})))

        ;; QtSvg.framework
        (let [qtsvg-fw-src (str qtsvg-dir "/lib/QtSvg.framework")]
          (when (and (fs/exists? qtsvg-fw-src)
                     (not (fs/exists? (str fw-dir "/QtSvg.framework"))))
            (println "  Supplementing: QtSvg.framework")
            (fs/copy-tree qtsvg-fw-src (str fw-dir "/QtSvg.framework") {:replace-existing true})
            (p/shell {:out :string :err :string} "chmod" "-R" "u+w" (str fw-dir "/QtSvg.framework")))))

      ;; QML modules — check if macdeployqt deployed them via -qmldir/-qmlimport
      (fs/create-dirs qml-dir)
      (when (and qtdecl-dir (not (fs/exists? (str qml-dir "/QtQuick"))))
        (println "  Supplementing: QML modules (QtCore, QtQml, QtQuick)")
        (let [qml-src (str qtdecl-dir "/lib/qt-6/qml")]
          (doseq [module ["QtCore" "QtQml" "QtQuick"]]
            (let [src (str qml-src "/" module)
                  dest (str qml-dir "/" module)]
              (when (and (fs/exists? src) (not (fs/exists? dest)))
                (fs/create-dirs dest)
                (fs/copy-tree src dest {:replace-existing true})
                (p/shell {:out :string :err :string} "chmod" "-R" "u+w" dest))))))

      (let [qt5c-qml (when qt5compat-dir (str qt5compat-dir "/lib/qt-6/qml"))
            qt5c-qml (or qt5c-qml
                         (some-> (first (fs/glob "/nix/store" "*-qt5compat-*/lib/qt-6/qml/Qt5Compat"))
                                 str fs/parent str))]
        (when (and qt5c-qml (not (fs/exists? (str qml-dir "/Qt5Compat"))))
          (println "  Supplementing: QML module Qt5Compat/GraphicalEffects")
          (let [src (str qt5c-qml "/Qt5Compat/GraphicalEffects")
                dest (str qml-dir "/Qt5Compat/GraphicalEffects")]
            (when (fs/exists? src)
              (fs/create-dirs dest)
              (fs/copy-tree src dest {:replace-existing true})
              (p/shell {:out :string :err :string} "chmod" "-R" "u+w" dest))))))

    ;; 7. App QML files
    (fs/create-dirs qml-dir)
    (fs/create-dirs (str res-dir "/resources"))
    (println "  QML: shell.qml")
    (fs/copy (str project-root "/qml/shell.qml") (str qml-dir "/shell.qml") {:replace-existing true})
    (let [example-qml-dir (str project-root "/examples/" example "/resources")]
      (doseq [f (fs/list-dir example-qml-dir)]
        (let [fname (str (fs/file-name f))]
          (if (fs/directory? f)
            (do
              (println (str "  QML: resources/" fname "/"))
              (fs/copy-tree (str f) (str res-dir "/resources/" fname) {:replace-existing true}))
            (do
              (println (str "  QML: resources/" fname))
              (fs/copy (str f) (str res-dir "/resources/" fname) {:replace-existing true}))))))

    ;; Make supplemented files writable
    (p/shell "chmod" "-R" "u+w" bundle-dir)

    ;; 8. Copy missing framework dependencies (QML plugins depend on frameworks
    ;;    that macdeployqt didn't see because they're not direct deps of the binary)
    (println "")
    (println "Copying missing framework dependencies...")
    (let [needed-fws (->> (concat (fs/glob qml-dir "**/*.dylib")
                                  (fs/glob plugins-dir "**/*.dylib"))
                          (mapcat #(otool-nix-deps (str %)))
                          (filter #(str/includes? % ".framework/"))
                          (map (fn [dep]
                                 (let [idx (str/index-of dep ".framework/")
                                       fw-path (subs dep 0 (+ idx (count ".framework")))
                                       fw-name (fs/file-name fw-path)]
                                   [fw-name fw-path])))
                          (into {}))]
      (doseq [[fw-name fw-src] (sort-by key needed-fws)]
        (let [fw-dest (str fw-dir "/" fw-name)]
          (when (and (fs/exists? fw-src) (not (fs/exists? fw-dest)))
            (println (str "  Framework: " fw-name))
            (fs/copy-tree fw-src fw-dest {:replace-existing true})
            (p/shell {:out :string :err :string} "chmod" "-R" "u+w" fw-dest))))

      ;; Transitive framework deps (one level — new frameworks may need others)
      (let [new-fws (->> (fs/glob fw-dir "*.framework/Versions/A/*")
                         (filter fs/regular-file?)
                         (remove #(str/ends-with? (str %) ".prl"))
                         (mapcat #(otool-nix-deps (str %)))
                         (filter #(str/includes? % ".framework/"))
                         (map (fn [dep]
                                (let [idx (str/index-of dep ".framework/")
                                      fw-path (subs dep 0 (+ idx (count ".framework")))
                                      fw-name (fs/file-name fw-path)]
                                  [fw-name fw-path])))
                         (into {}))]
        (doseq [[fw-name fw-src] (sort-by key new-fws)]
          (let [fw-dest (str fw-dir "/" fw-name)]
            (when (and (fs/exists? fw-src) (not (fs/exists? fw-dest)))
              (println (str "  Framework (transitive): " fw-name))
              (fs/copy-tree fw-src fw-dest {:replace-existing true})
              (p/shell {:out :string :err :string} "chmod" "-R" "u+w" fw-dest))))))

    (p/shell "chmod" "-R" "u+w" bundle-dir)

    ;; 9. Fix remaining nix refs that macdeployqt missed
    (println "")
    (println "Fixing remaining nix references...")
    (fix-remaining-nix-refs! plugins-dir contents-dir)
    (fix-remaining-nix-refs! qml-dir contents-dir)
    (fix-remaining-nix-refs! fw-dir contents-dir)

    ;; 9. Generate launcher script
    (println "")
    (println "Generating launcher script...")
    (let [launcher-path (str macos-dir "/launch")
          launcher-content (str "#!/bin/bash\n"
                                "DIR=\"$(cd \"$(dirname \"$0\")/..\" && pwd)\"\n"
                                "export DYLD_FRAMEWORK_PATH=\"$DIR/Frameworks\"\n"
                                "export DYLD_LIBRARY_PATH=\"$DIR/Frameworks\"\n"
                                "cd \"$DIR/Resources\"\n"
                                "exec \"$DIR/MacOS/cuirq-" example "\" "
                                "\"-Djava.library.path=$DIR/Frameworks\"\n")]
      (spit launcher-path launcher-content)
      (p/shell "chmod" "+x" launcher-path))

    ;; 10. Report size
    (println "")
    (let [total-size (->> (fs/glob bundle-dir "**")
                          (filter fs/regular-file?)
                          (map #(fs/size %))
                          (reduce + 0))
          size-mb (/ total-size 1048576.0)]
      (println (str app-name ".app created: build/" app-name ".app"))
      (println (str "Total size: " (format "%.1f" size-mb) " MB"))
      (println "")
      (println (str "Run with:  open build/" app-name ".app"))
      (println (str "       or: build/" app-name ".app/Contents/MacOS/launch")))))
