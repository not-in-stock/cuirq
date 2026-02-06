#ifndef PANAMA_API_H
#define PANAMA_API_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

bool cuirq_initialize(int argc, char** argv);
void cuirq_shutdown(void);
int  cuirq_exec(void);
void cuirq_quit(void);

bool cuirq_load_qml(const char* path);
void cuirq_set_property(const char* name, const char* json_value);

typedef void (*cuirq_signal_callback_t)(const char* name, const char* json_args);
void cuirq_set_signal_callback(cuirq_signal_callback_t callback);
void cuirq_register_signal(const char* name);

void cuirq_create_model(const char* name);
void cuirq_set_model_data(const char* name, const char* json_data);
void cuirq_clear_model(const char* name);
int  cuirq_get_model_count(const char* name);

void cuirq_set_auto_reload(bool enabled);
bool cuirq_is_auto_reload_enabled(void);

#ifdef __cplusplus
}
#endif

#endif // PANAMA_API_H
