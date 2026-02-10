#include "panama_api.h"
#include "qt_engine.h"

extern "C" {

bool cuirq_initialize(int argc, char** argv) {
    return cuirq::initialize(argc, argv);
}

void cuirq_shutdown(void) {
    cuirq::shutdown();
}

int cuirq_exec(void) {
    return cuirq::exec();
}

void cuirq_quit(void) {
    cuirq::quit();
}

bool cuirq_load_qml(const char* path) {
    return cuirq::load_qml(path);
}

void cuirq_set_app_name(const char* name) {
    cuirq::set_app_name(name);
}

void cuirq_set_property(const char* name, const char* json_value) {
    cuirq::set_context_property(name, json_value);
}

void cuirq_set_signal_callback(cuirq_signal_callback_t callback) {
    cuirq::set_signal_callback(callback);
}

void cuirq_register_signal(const char* name) {
    cuirq::register_signal_handler(name);
}

void cuirq_create_model(const char* name) {
    cuirq::create_model(name);
}

void cuirq_set_model_data(const char* name, const char* json_data) {
    cuirq::set_model_data(name, json_data);
}

void cuirq_update_model_data(const char* name, const char* json_data, const char* key_field) {
    cuirq::update_model_data(name, json_data, key_field);
}

void cuirq_clear_model(const char* name) {
    cuirq::clear_model(name);
}

int cuirq_get_model_count(const char* name) {
    return cuirq::get_model_count(name);
}

void cuirq_sort_model(const char* name, const char* role, bool ascending) {
    cuirq::sort_model(name, role, ascending);
}

void cuirq_set_auto_reload(bool enabled) {
    cuirq::set_auto_reload(enabled);
}

bool cuirq_is_auto_reload_enabled(void) {
    return cuirq::is_auto_reload_enabled();
}

void cuirq_start_directory_watch(const char* path) {
    cuirq::start_directory_watch(path);
}

void cuirq_stop_directory_watch(void) {
    cuirq::stop_directory_watch();
}

void cuirq_hide_titlebar(void) {
    cuirq::hide_titlebar();
}

void cuirq_enable_sidebar_vibrancy(int width) {
    cuirq::enable_sidebar_vibrancy(width);
}

void cuirq_enable_toolbar_vibrancy(int sidebarWidth, int toolbarHeight) {
    cuirq::enable_toolbar_vibrancy(sidebarWidth, toolbarHeight);
}

void cuirq_set_vibrancy_appearance(const char* mode) {
    cuirq::set_vibrancy_appearance(mode);
}

void cuirq_set_vibrancy_always_active(bool always) {
    cuirq::set_vibrancy_always_active(always);
}

} // extern "C"
