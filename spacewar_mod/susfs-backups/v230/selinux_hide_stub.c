#include "selinux_hide.h"
#include <security.h>

bool ksu_selinux_hide_enabled __read_mostly = false;
bool ksu_selinux_hide_running __read_mostly = false;
struct selinux_state fake_state;
struct page *fake_status = NULL;
DEFINE_STATIC_KEY_FALSE(fake_status_initialize_key);

void initialize_fake_status(void) { }

void ksu_selinux_hide_init(void) { }
void ksu_selinux_hide_exit(void) { }
void ksu_selinux_hide_drop_backup_if_unused(void) { }
void ksu_selinux_hide_handle_second_stage(void) { }
void ksu_selinux_hide_handle_post_fs_data(void) { }
