#ifndef QT_ENGINE_H
#define QT_ENGINE_H

namespace cuirq {

// Signal callback type: receives signal name and JSON-encoded arguments
using signal_callback_t = void(*)(const char* name, const char* json_args);

// Lifecycle
bool initialize(int argc, char* argv[]);
void set_app_name(const char* name);
void shutdown();
int exec();
void quit();

// QML
bool load_qml(const char* path);

// Properties
void set_context_property(const char* name, const char* json_value);

// Signals
void set_signal_callback(signal_callback_t callback);
void register_signal_handler(const char* name);

// Models
void create_model(const char* name);
void set_model_data(const char* name, const char* json_data);
void update_model_data(const char* name, const char* json_data, const char* key_field);
void clear_model(const char* name);
int get_model_count(const char* name);

// Hot-reload
void set_auto_reload(bool enabled);
bool is_auto_reload_enabled();

// Directory watching
void start_directory_watch(const char* path);
void stop_directory_watch();

// Platform
void hide_titlebar();
void enable_sidebar_vibrancy(int width);
void enable_toolbar_vibrancy(int sidebarWidth, int toolbarHeight);
void set_vibrancy_appearance(const char* mode);

} // namespace cuirq

#endif // QT_ENGINE_H
