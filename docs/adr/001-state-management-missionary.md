# ADR-001: Declarative State Management

## Status
Accepted — partially implemented

## Context

cuirq is a framework for building desktop applications in Clojure with Qt/QML UI. We need a state management system that is:

1. **Lightweight** — without re-frame overhead (registries, interceptors, keyword-based dispatch)
2. **Reactive** — automatic UI updates when data changes
3. **Multi-layered** — raw data -> derived -> QML-ready, with automatic propagation
4. **I/O-friendly** — async operations on virtual threads without callback hell
5. **Multi-window ready** — global vs per-window state decomposition (see ADR-007)
6. **Performance-first** — transducers for single-pass transforms, diffing before QML push

### Alternatives Considered

| Solution | Pros | Cons |
|----------|------|------|
| **re-frame** | Mature, multi-level subscriptions | Heavy registries, ClojureScript-oriented, keyword dispatch overhead |
| **missionary** | Reactive flows, function composition, Virtual Threads, cancellation | Less known, requires learning |
| **core.async** | Well-known CSP model | Different concurrency model, no built-in reactivity |
| **atom + watcher** | Zero deps, simple | No derived values, no backpressure, manual everything |

## Decision

Two-layer architecture with missionary for reactive composition:

1. **cuirq.state** — base layer on atoms, works standalone for simple apps (counter)
2. **cuirq.reactive** — optional missionary layer for derived flows and auto-sync

Key principles:
- **No registries** — "subscriptions" are just `m/latest` compositions, plain functions
- **Transducers first** — single-pass transforms at every stage
- **Multi-window native** — single atom with global/per-window decomposition (future)
- **Pluggable native utilities** — C++ plugins for hot-path I/O (FSEvents, batch stat)

## What's Implemented

### Framework namespaces

```
cuirq.core             Cross-platform Qt API: with-qt, load-qml!, exec!, quit!,
                       set-property!, on-signal!, directory watching
cuirq.macos.window     macOS-specific: titlebar, vibrancy, app name
cuirq.state            Atom-based state with auto-sync to QML context properties
cuirq.reactive         Missionary flows: subscribe!, sync-props!
cuirq.models           List model API: create-model!, set-data!, update-data!
```

### File manager module structure

```
file-manager.nav       Pure nav state: *nav atom, nav-push/back/forward, nav-flow
file-manager.miller    Miller columns: pool, *state, navigate-to!, select!, refresh-column!
file-manager.views     Flat views: *view-mode, *sort-state, navigate-flat!, refresh-file-list!
file-manager.sync      Reactive sync setup: start! (binds nav + miller flows to QML props)
file-manager.signals   Signal dispatch: dispatch-navigate!, navigate-to!, go-back!/forward!, register-all!
file-manager.core      Slim orchestrator: -main + :gen-class
file-manager.dirs      Directory cache layer (unchanged)
file-manager.tree      Tree expand/collapse + flat list builder (unchanged)
```

Dependency graph (acyclic):

```
nav (pure, no side effects)
 ↑
miller → nav, dirs
views  → nav, dirs, tree
 ↑
sync → nav, miller
 ↑
signals → nav, miller, views, dirs, tree
 ↑
core → miller, sync, signals
```

### Reactive layer — what works today

Navigation properties (`currentPath`, `canGoBack`, `canGoForward`, `breadcrumbs`) and miller column state (`millerActiveCount`, `millerColumns`) are **fully reactive** via missionary flows. Declared once in `sync/start!`, auto-propagated on atom change:

```clojure
;; file-manager.sync — the entire reactive setup
(reactive/sync-props!
  {"currentPath"       (m/latest :path nav/nav-flow)
   "canGoBack"         (m/latest #(boolean (seq (:back %))) nav/nav-flow)
   "canGoForward"      (m/latest #(boolean (seq (:forward %))) nav/nav-flow)
   "breadcrumbs"       (m/latest #(json/write-str (build-breadcrumbs (:path %))) nav/nav-flow)
   "millerActiveCount" (m/latest :active-count miller/state-flow)
   "millerColumns"     (m/latest #(json/write-str ...) miller/state-flow)})
```

### Side-effect grouping — what works today

Navigation dispatch is centralized via `dispatch-navigate!` — one function handles cache invalidation and view-mode branching. The three nav functions (`navigate-to!`, `go-back!`, `go-forward!`) are now 4-10 lines each:

```clojure
;; file-manager.signals
(defn- dispatch-navigate! [path]
  (if (= @views/*view-mode "columns")
    (do (dirs/invalidate-all!)
        (miller/navigate-to! path))
    (views/navigate-flat! path)))

(defn go-back! []
  (when (seq (:back @nav/*nav))
    (swap! nav/*nav nav/nav-back)
    (dispatch-navigate! (:path @nav/*nav))))
```

### Simple app — base layer only (counter)

```clojure
(ns counter.core
  (:require [cuirq.core :as cuirq]
            [cuirq.state :as state]))

;; Atom-based, no missionary needed
(state/set-state! {:count 0 :message "Hello cuirq!"})
;; Signal handlers mutate state; QML reads directly
```

## What's Not Yet Implemented

### 1. Multi-window state decomposition

Currently each atom is standalone (`nav/*nav`, `miller/*state`, `views/*view-mode`). The plan is a single atom with `{:global {...} :windows {id {...}}}` shape and `window-flow` scoping:

```clojure
;; Future: scoped per-window flows
(defn window-flow [win-id key]
  (m/latest #(get-in % [:windows win-id key]) (m/watch *app)))

;; Pure state transitions parameterized by window-id
(defn navigate [state win-id path]
  (-> state
      (update-in [:windows win-id :history :back] conj (get-in state [:windows win-id :path]))
      (assoc-in  [:windows win-id :history :forward] [])
      (assoc-in  [:windows win-id :path] path)))
```

Blocked on: ADR-007 (multi-window support at C++ level).

### 2. Reactive model sync

Currently models are pushed imperatively (`models/set-data!`, `models/update-data!`) in signal handlers. The goal is `sync-model!` — a flow that auto-pushes model data on change:

```clojure
;; Future: declarative model binding
(sync-model! :files files-flow)
```

Requires: `m/observe` integration with directory watcher signals to trigger re-reads as a flow rather than imperative `invalidate! + refresh!`.

### 3. Native signal → missionary flow bridge

```clojure
;; Future: FSEvents as a flow, not a callback
(def dir-changed-flow
  (m/observe
    (fn [emit!]
      (cuirq/on-signal! :directoryChanged (fn [_ args] (emit! args)))
      #(cuirq/remove-signal-handler! :directoryChanged))))

;; Files auto-refresh when path OR sort OR fs-event changes
(def files-flow
  (m/latest
    (fn [path sort-state _trigger]
      (into [] visible-files-xf
        (sort-by (sort-fn sort-state) (list-dir path))))
    path-flow sort-flow (m/relieve {} dir-changed-flow)))
```

### 4. Transducer pipelines for model data

```clojure
;; Future: reusable transform pipelines
(def grid-view-xf
  (comp
    (remove :hidden?)
    (map #(select-keys % [:name :path :isDir :size :fileType]))))

(sync-model! :files files-flow grid-view-xf)
```

## Consequences

### Positive

1. **Modularity** — base layer works without dependencies, reactive is optional
2. **No registries** — flows are functions, composed with `m/latest`, no keyword dispatch
3. **Proven in practice** — 6 reactive props auto-synced, zero manual push for nav state
4. **Side-effect grouping** — `dispatch-navigate!` + `navigate-flat!` eliminated ~65 lines of duplication
5. **Clean module boundaries** — acyclic dependency graph, each namespace has one responsibility
6. **Cancellation** — all reactive subscriptions return cancel functions
7. **Testability** — pure nav functions (`nav-push`, `nav-back`, `nav-forward`) are trivially testable

### Negative

1. **Learning curve** — missionary is less known than core.async (mitigated: simple base layer works standalone)
2. **Hybrid state** — some props are reactive (nav, miller columns), others are still imperative (itemCount, viewMode, sort) — will converge as more flows are added
3. **Two model push paths** — `models/set-data!` (full replace) and `models/update-data!` (incremental diff) coexist; future `sync-model!` should unify them

## References

- [Missionary Documentation](https://github.com/leonoel/missionary)
- [Java Virtual Threads (JEP 444)](https://openjdk.org/jeps/444)
- ADR-006: Hot Reload Improvements (proxy window, engine-per-reload)
- ADR-007: Multi-Window Support (engine-per-window, WindowManager)
