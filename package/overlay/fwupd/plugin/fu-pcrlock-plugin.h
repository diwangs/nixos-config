/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#pragma once

#include <fwupdplugin.h>

#define FU_TYPE_PCRLOCK_PLUGIN (fu_pcrlock_plugin_get_type())
G_DECLARE_FINAL_TYPE(FuPcrlockPlugin, fu_pcrlock_plugin, FU, PCRLOCK_PLUGIN, FuPlugin)

typedef enum {
	FU_PCRLOCK_COMPONENT_NONE = 0,
	FU_PCRLOCK_COMPONENT_FIRMWARE_CODE = 1 << 0,
	FU_PCRLOCK_COMPONENT_SECURE_BOOT = 1 << 1,
} FuPcrlockComponent;

guint
fu_pcrlock_plugin_device_mask(FuDevice *device);
guint
fu_pcrlock_plugin_get_deferred_mask(FuPcrlockPlugin *self);
guint
fu_pcrlock_plugin_get_pending_mask(FuPcrlockPlugin *self);
void
fu_pcrlock_plugin_set_helper_path(FuPcrlockPlugin *self, const gchar *path);
void
fu_pcrlock_plugin_set_state_path(FuPcrlockPlugin *self, const gchar *path);
