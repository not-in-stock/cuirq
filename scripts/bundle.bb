(ns bundle
  "Create a self-contained macOS .app bundle from a native binary."
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

(defn- collect-nix-dylibs
  "Recursively collect all /nix/store dylib paths reachable from `path`."
  [path]
  (loop [queue #{(str path)}
         seen  #{}]
    (if (empty? queue)
      seen
      (let [current (first queue)
            rest-q  (disj queue current)]
        (if (seen current)
          (recur rest-q seen)
          (let [deps (otool-nix-deps current)
                new-deps (remove seen deps)]
            (recur (into rest-q new-deps)
                   (conj seen current))))))))

(defn- framework-dir
  "Given a nix path like /nix/.../lib/QtCore.framework/Versions/A/QtCore,
   return the .framework directory path: /nix/.../lib/QtCore.framework"
  [nix-path]
  (when-let [idx (str/index-of nix-path ".framework/")]
    (subs nix-path 0 (+ idx (count ".framework")))))

(defn- framework?
  "True if this nix dep path is inside a .framework bundle."
  [nix-path]
  (str/includes? nix-path ".framework/"))

(defn- rpath-ref
  "Given a nix dep path, return the @rpath reference to use.
   Framework: @rpath/QtCore.framework/Versions/A/QtCore
   Dylib:     @rpath/libfoo.dylib"
  [nix-path]
  (if (framework? nix-path)
    (let [fw-dir (framework-dir nix-path)
          fw-name (fs/file-name fw-dir)
          ;; relative path inside framework
          rel (subs nix-path (inc (count (str (fs/parent fw-dir)))))]
      (str "@rpath/" rel))
    (str "@rpath/" (fs/file-name nix-path))))

(defn- fix-nix-refs!
  "Rewrite all /nix/store references in `path` to @rpath/... form."
  [path]
  (let [deps (otool-nix-deps (str path))]
    (doseq [dep deps]
      (p/shell "install_name_tool" "-change" dep (rpath-ref dep) (str path))))
  ;; Fix install name (id)
  (let [fname (str (fs/file-name path))
        ;; Check if this file is inside a framework in the bundle
        path-str (str path)
        id (if (str/includes? path-str ".framework/")
             (let [idx (str/index-of path-str ".framework/")
                   ;; Find the framework dir name
                   before (subs path-str 0 idx)
                   fw-basename (fs/file-name before)
                   after (subs path-str (inc idx))]
               (str "@rpath/" fw-basename ".framework/" after))
             (str "@rpath/" fname))]
    (p/shell "install_name_tool" "-id" id (str path))))

(defn- copy-qml-module!
  "Copy a QML module directory to the bundle's PlugIns/qml/ dir."
  [src-dir dest-dir module-path]
  (let [src  (str src-dir "/" module-path)
        dest (str dest-dir "/" module-path)]
    (when (fs/exists? src)
      (fs/create-dirs dest)
      (fs/copy-tree src dest {:replace-existing true})
      (p/shell {:out :string :err :string} "chmod" "-R" "u+w" dest)
      (println (str "  QML module: " module-path)))))

(defn- fix-plugin-rpaths!
  "Fix rpaths for all dylibs under a plugin directory."
  [plugin-dir]
  (doseq [dylib (fs/glob plugin-dir "**/*.dylib")]
    (let [dylib-str (str dylib)]
      (fix-nix-refs! dylib-str)
      (let [rel (fs/relativize plugin-dir dylib)
            depth (dec (count (fs/components rel)))
            up-segments (str/join "/" (repeat (inc depth) ".."))
            rpath (str "@loader_path/" up-segments "/Frameworks")]
        (try
          (p/shell "install_name_tool" "-add_rpath" rpath dylib-str)
          (catch Exception _ nil))))))

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
        plugins-dir  (str contents-dir "/PlugIns")]

    ;; Validate inputs
    (when-not (fs/exists? native-bin)
      (println (str "Error: Native binary not found: " native-bin))
      (println "Run 'bb aot " example " && bb native " example "' first.")
      (System/exit 1))
    (when-not (fs/exists? bridge-lib)
      (println "Error: libqmlbridge.dylib not found. Run 'bb build' first.")
      (System/exit 1))

    ;; Clean previous bundle
    (when (fs/exists? bundle-dir)
      (p/shell "chmod" "-R" "u+w" bundle-dir)
      (fs/delete-tree bundle-dir))

    (println (str "Creating " app-name ".app ..."))
    (println "")

    ;; Create directory structure
    (doseq [d [macos-dir fw-dir (str res-dir "/qml") (str res-dir "/resources")
               (str plugins-dir "/platforms") (str plugins-dir "/qml")]]
      (fs/create-dirs d))

    ;; 1. Copy native binary
    (println (str "  Binary: cuirq-" example))
    (fs/copy native-bin (str macos-dir "/cuirq-" example) {:replace-existing true})
    (p/shell "chmod" "+x" (str macos-dir "/cuirq-" example))

    ;; 2. Copy libqmlbridge.dylib
    (println "  Bridge: libqmlbridge.dylib")
    (fs/copy bridge-lib (str fw-dir "/libqmlbridge.dylib") {:replace-existing true})

    ;; 3. Copy QML files
    (println "  QML: shell.qml")
    (fs/copy (str project-root "/qml/shell.qml") (str res-dir "/qml/shell.qml") {:replace-existing true})
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

    ;; 4. Collect and copy all nix dependencies (recursive)
    (println "")
    (println "Collecting native dependencies...")
    (let [all-nix-paths (into (collect-nix-dylibs bridge-lib)
                              (collect-nix-dylibs native-bin))
          nix-deps      (->> all-nix-paths
                             (filter #(str/starts-with? % "/nix/store/"))
                             (remove #{bridge-lib})
                             sort)
          ;; Separate framework deps from plain dylibs
          fw-deps   (filter framework? nix-deps)
          dylib-deps (remove framework? nix-deps)
          ;; Deduplicate frameworks by .framework dir
          fw-dirs   (->> fw-deps
                         (map framework-dir)
                         distinct)]

      ;; Copy full .framework bundles
      (doseq [fw-src fw-dirs]
        (let [fw-name (fs/file-name fw-src)
              fw-dest (str fw-dir "/" fw-name)]
          (when-not (fs/exists? fw-dest)
            (println (str "  Framework: " fw-name))
            (fs/copy-tree fw-src fw-dest {:replace-existing true})
            (p/shell {:out :string :err :string} "chmod" "-R" "u+w" fw-dest))))

      ;; Copy plain dylibs
      (doseq [dep dylib-deps]
        (let [basename (str (fs/file-name dep))]
          (when-not (fs/exists? (str fw-dir "/" basename))
            (println (str "  Library: " basename))
            (fs/copy dep (str fw-dir "/" basename) {:replace-existing true}))))

      ;; 5. Copy Qt platform plugin
      (println "")
      (println "Copying Qt plugins...")
      (let [qtbase-path (->> nix-deps
                             (filter #(str/includes? % "qtbase"))
                             first)
            qtbase-dir  (when qtbase-path
                          (let [parts (str/split qtbase-path #"/")]
                            (str "/" (str/join "/" (take 4 parts)))))
            qtdecl-path (->> nix-deps
                             (filter #(str/includes? % "qtdeclarative"))
                             first)
            qtdecl-dir  (when qtdecl-path
                          (let [parts (str/split qtdecl-path #"/")]
                            (str "/" (str/join "/" (take 4 parts)))))
            qt5compat-qml (let [qt5c-dep (->> nix-deps
                                              (filter #(str/includes? % "qt5compat"))
                                              first)]
                            (when qt5c-dep
                              (let [parts (str/split qt5c-dep #"/")]
                                (str "/" (str/join "/" (take 4 parts)) "/lib/qt-6/qml"))))]

        ;; Platform plugin
        (when qtbase-dir
          (let [cocoa-src (str qtbase-dir "/lib/qt-6/plugins/platforms/libqcocoa.dylib")]
            (when (fs/exists? cocoa-src)
              (println "  Plugin: platforms/libqcocoa.dylib")
              (fs/copy cocoa-src (str plugins-dir "/platforms/libqcocoa.dylib") {:replace-existing true})
              ;; Copy cocoa's deps (frameworks + dylibs)
              (doseq [dep (otool-nix-deps cocoa-src)]
                (if (framework? dep)
                  (let [fw-src (framework-dir dep)
                        fw-name (fs/file-name fw-src)
                        fw-dest (str fw-dir "/" fw-name)]
                    (when-not (fs/exists? fw-dest)
                      (println (str "  Framework (cocoa dep): " fw-name))
                      (fs/copy-tree fw-src fw-dest {:replace-existing true})
                      (p/shell {:out :string :err :string} "chmod" "-R" "u+w" fw-dest)))
                  (let [basename (str (fs/file-name dep))]
                    (when-not (fs/exists? (str fw-dir "/" basename))
                      (println (str "  Library (cocoa dep): " basename))
                      (fs/copy dep (str fw-dir "/" basename) {:replace-existing true}))))))))

        ;; Image format plugins (QtSvg for SVG icon support)
        (let [qtsvg-path (->> nix-deps
                              (filter #(str/includes? % "qtsvg"))
                              first)
              qtsvg-dir  (when qtsvg-path
                           (let [parts (str/split qtsvg-path #"/")]
                             (str "/" (str/join "/" (take 4 parts)))))
              ;; Also try to find qtsvg from nix store if not in direct deps
              qtsvg-dir  (or qtsvg-dir
                             (let [found (first (fs/glob "/nix/store" "*-qtsvg-*/lib/qt-6/plugins/imageformats/libqsvg.dylib"))]
                               (when found
                                 (let [parts (str/split (str found) #"/")]
                                   (str "/" (str/join "/" (take 4 parts)))))))]
          (when qtsvg-dir
            (let [imgfmt-dir (str plugins-dir "/imageformats")
                  svg-src    (str qtsvg-dir "/lib/qt-6/plugins/imageformats/libqsvg.dylib")
                  icon-src   (str qtsvg-dir "/lib/qt-6/plugins/iconengines/libqsvgicon.dylib")]
              (fs/create-dirs imgfmt-dir)
              (when (fs/exists? svg-src)
                (println "  Plugin: imageformats/libqsvg.dylib")
                (fs/copy svg-src (str imgfmt-dir "/libqsvg.dylib") {:replace-existing true}))
              (when (fs/exists? icon-src)
                (let [iconeng-dir (str plugins-dir "/iconengines")]
                  (fs/create-dirs iconeng-dir)
                  (println "  Plugin: iconengines/libqsvgicon.dylib")
                  (fs/copy icon-src (str iconeng-dir "/libqsvgicon.dylib") {:replace-existing true})))
              ;; Copy QtSvg.framework dependency
              (let [qtsvg-fw-src (str qtsvg-dir "/lib/QtSvg.framework")]
                (when (and (fs/exists? qtsvg-fw-src)
                           (not (fs/exists? (str fw-dir "/QtSvg.framework"))))
                  (println "  Framework: QtSvg.framework")
                  (fs/copy-tree qtsvg-fw-src (str fw-dir "/QtSvg.framework") {:replace-existing true})
                  (p/shell {:out :string :err :string} "chmod" "-R" "u+w" (str fw-dir "/QtSvg.framework")))))))

        ;; QML modules from qtdeclarative
        (when qtdecl-dir
          (let [qml-src (str qtdecl-dir "/lib/qt-6/qml")]
            (doseq [module ["QtCore" "QtQml" "QtQuick"]]
              (copy-qml-module! qml-src (str plugins-dir "/qml") module))))

        ;; Qt5Compat
        (when qt5compat-qml
          (copy-qml-module! qt5compat-qml (str plugins-dir "/qml") "Qt5Compat/GraphicalEffects"))

        (when (and (not qt5compat-qml) (fs/exists? (str plugins-dir "/qml")))
          (let [qt5c-glob (fs/glob "/nix/store" "*-qt5compat-*/lib/qt-6/qml/Qt5Compat")]
            (when-let [qt5c-dir (first qt5c-glob)]
              (copy-qml-module! (str (fs/parent qt5c-dir)) (str plugins-dir "/qml") "Qt5Compat/GraphicalEffects")))))

      ;; 6. Collect deps from QML plugin dylibs
      (println "")
      (println "Collecting QML plugin dependencies...")
      (doseq [dylib (fs/glob plugins-dir "**/*.dylib")]
        (doseq [dep (otool-nix-deps (str dylib))]
          (if (framework? dep)
            (let [fw-src (framework-dir dep)
                  fw-name (fs/file-name fw-src)
                  fw-dest (str fw-dir "/" fw-name)]
              (when-not (fs/exists? fw-dest)
                (println (str "  Framework (plugin dep): " fw-name))
                (fs/copy-tree fw-src fw-dest {:replace-existing true})
                (p/shell {:out :string :err :string} "chmod" "-R" "u+w" fw-dest)
                ;; One level of transitive deps
                (let [fw-bin (str fw-dest "/Versions/A/" (str/replace fw-name ".framework" ""))]
                  (when (fs/exists? fw-bin)
                    (doseq [tdep (otool-nix-deps fw-bin)]
                      (if (framework? tdep)
                        (let [tfw-src (framework-dir tdep)
                              tfw-name (fs/file-name tfw-src)
                              tfw-dest (str fw-dir "/" tfw-name)]
                          (when-not (fs/exists? tfw-dest)
                            (println (str "  Framework (transitive): " tfw-name))
                            (fs/copy-tree tfw-src tfw-dest {:replace-existing true})
                            (p/shell {:out :string :err :string} "chmod" "-R" "u+w" tfw-dest)))
                        (let [tbase (str (fs/file-name tdep))]
                          (when-not (fs/exists? (str fw-dir "/" tbase))
                            (println (str "  Library (transitive): " tbase))
                            (fs/copy tdep (str fw-dir "/" tbase) {:replace-existing true})))))))))
            (let [basename (str (fs/file-name dep))]
              (when-not (fs/exists? (str fw-dir "/" basename))
                (println (str "  Library (plugin dep): " basename))
                (fs/copy dep (str fw-dir "/" basename) {:replace-existing true})
                ;; Transitive deps
                (doseq [tdep (otool-nix-deps dep)]
                  (let [tbase (str (fs/file-name tdep))]
                    (when-not (fs/exists? (str fw-dir "/" tbase))
                      (println (str "  Library (transitive): " tbase))
                      (fs/copy tdep (str fw-dir "/" tbase) {:replace-existing true})))))))))

      ;; Make everything writable
      (p/shell "chmod" "-R" "u+w" bundle-dir)

      ;; 7. Fix rpaths in Frameworks
      (println "")
      (println "Fixing rpaths in Frameworks...")
      ;; Plain dylibs
      (doseq [dylib (fs/glob fw-dir "*.dylib")]
        (fix-nix-refs! (str dylib)))
      ;; Framework binaries
      (doseq [fw (fs/glob fw-dir "*.framework")]
        (let [fw-name (str/replace (str (fs/file-name fw)) ".framework" "")
              fw-bin  (str fw "/Versions/A/" fw-name)]
          (when (fs/exists? fw-bin)
            (fix-nix-refs! fw-bin))))

      ;; Add @loader_path rpath to plain dylibs
      (doseq [dylib (fs/glob fw-dir "*.dylib")]
        (try
          (p/shell "install_name_tool" "-add_rpath" "@loader_path" (str dylib))
          (catch Exception _ nil)))
      ;; Add rpath to framework binaries (they need to find sibling frameworks)
      (doseq [fw (fs/glob fw-dir "*.framework")]
        (let [fw-name (str/replace (str (fs/file-name fw)) ".framework" "")
              fw-bin  (str fw "/Versions/A/" fw-name)]
          (when (fs/exists? fw-bin)
            (try
              (p/shell "install_name_tool" "-add_rpath" "@loader_path/../../.." (str fw-bin))
              (catch Exception _ nil)))))

      ;; 8. Fix rpaths in PlugIns
      (println "Fixing rpaths in PlugIns...")
      (fix-plugin-rpaths! plugins-dir)

      ;; 9. Fix rpaths in the native binary
      (println "Fixing rpaths in binary...")
      (let [bin-path (str macos-dir "/cuirq-" example)]
        (fix-nix-refs! bin-path)
        (try
          (p/shell "install_name_tool" "-add_rpath" "@executable_path/../Frameworks" bin-path)
          (catch Exception _ nil))))

    ;; 10. Generate launcher script
    (println "")
    (println "Generating launcher script...")
    (let [launcher-path (str macos-dir "/launch")
          launcher-content (str "#!/bin/bash\n"
                                "DIR=\"$(cd \"$(dirname \"$0\")/..\" && pwd)\"\n"
                                "export QML2_IMPORT_PATH=\"$DIR/PlugIns/qml\"\n"
                                "export QT_PLUGIN_PATH=\"$DIR/PlugIns\"\n"
                                "export DYLD_FRAMEWORK_PATH=\"$DIR/Frameworks\"\n"
                                "export DYLD_LIBRARY_PATH=\"$DIR/Frameworks\"\n"
                                "cd \"$DIR/Resources\"\n"
                                "exec \"$DIR/MacOS/cuirq-" example "\" "
                                "\"-Djava.library.path=$DIR/Frameworks\"\n")]
      (spit launcher-path launcher-content)
      (p/shell "chmod" "+x" launcher-path))

    ;; 11. Generate Info.plist
    (let [plist-path (str contents-dir "/Info.plist")
          bundle-id  (str "com.cuirq." (str/replace example "-" ""))
          plist-content (str "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                             "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
                             "<plist version=\"1.0\">\n"
                             "<dict>\n"
                             "    <key>CFBundleExecutable</key>\n"
                             "    <string>launch</string>\n"
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
                             "</plist>\n")]
      (spit plist-path plist-content))

    ;; Done — report size
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
