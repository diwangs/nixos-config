/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#include "config.h"

#include <errno.h>
#include <glib/gstdio.h>

#include "fu-pcrlock-plugin.h"

#define FU_PCRLOCK_HELPER_PATH "@PCRLOCK_HELPER@"
#define FU_PCRLOCK_STATE_PATH  "@PCRLOCK_STATE@"
#define FU_PCRLOCK_STATE_GROUP "Pcrlock"

typedef struct {
	guint mask;
	gboolean write_started;
} FuPcrlockTransaction;

struct _FuPcrlockPlugin {
	FuPlugin parent_instance;
	GHashTable *transactions;
	guint deferred_mask;
	gchar *helper_path;
	gchar *state_path;
	gchar *state_error;
};

G_DEFINE_TYPE(FuPcrlockPlugin, fu_pcrlock_plugin, FU_TYPE_PLUGIN)

static void
fu_pcrlock_transaction_free(FuPcrlockTransaction *transaction)
{
	g_free(transaction);
}

guint
fu_pcrlock_plugin_device_mask(FuDevice *device)
{
	const gchar *plugin = fu_device_get_plugin(device);

	if (g_strcmp0(plugin, "uefi_capsule") == 0 &&
	    fu_device_has_private_flag(device, FU_DEVICE_PRIVATE_FLAG_HOST_FIRMWARE))
		return FU_PCRLOCK_COMPONENT_FIRMWARE_CODE;

	if (g_strcmp0(plugin, "uefi_db") == 0 ||
	    g_strcmp0(plugin, "uefi_dbx") == 0 ||
	    g_strcmp0(plugin, "uefi_kek") == 0 ||
	    g_strcmp0(plugin, "uefi_pk") == 0)
		return FU_PCRLOCK_COMPONENT_SECURE_BOOT;

	return FU_PCRLOCK_COMPONENT_NONE;
}

guint
fu_pcrlock_plugin_get_pending_mask(FuPcrlockPlugin *self)
{
	GHashTableIter iter;
	FuPcrlockTransaction *transaction;
	guint mask = FU_PCRLOCK_COMPONENT_NONE;

	g_return_val_if_fail(FU_IS_PCRLOCK_PLUGIN(self), FU_PCRLOCK_COMPONENT_NONE);

	g_hash_table_iter_init(&iter, self->transactions);
	while (g_hash_table_iter_next(&iter, NULL, (gpointer *)&transaction))
		mask |= transaction->mask;
	return mask;
}

guint
fu_pcrlock_plugin_get_deferred_mask(FuPcrlockPlugin *self)
{
	g_return_val_if_fail(FU_IS_PCRLOCK_PLUGIN(self), FU_PCRLOCK_COMPONENT_NONE);
	return self->deferred_mask;
}

static guint
fu_pcrlock_plugin_get_pending_mask_except(FuPcrlockPlugin *self, const gchar *device_id)
{
	GHashTableIter iter;
	FuPcrlockTransaction *transaction;
	gpointer key;
	guint mask = FU_PCRLOCK_COMPONENT_NONE;

	g_hash_table_iter_init(&iter, self->transactions);
	while (g_hash_table_iter_next(&iter, &key, (gpointer *)&transaction)) {
		if (g_strcmp0(key, device_id) != 0)
			mask |= transaction->mask;
	}
	return mask;
}

static gboolean
fu_pcrlock_plugin_save_state(FuPcrlockPlugin *self, GError **error)
{
	guint pending_mask = fu_pcrlock_plugin_get_pending_mask(self);
	g_autofree gchar *dirname = NULL;
	g_autofree gchar *data = NULL;
	g_autoptr(GKeyFile) keyfile = NULL;
	gsize data_size = 0;

	if (pending_mask == FU_PCRLOCK_COMPONENT_NONE &&
	    self->deferred_mask == FU_PCRLOCK_COMPONENT_NONE) {
		if (g_unlink(self->state_path) < 0 && errno != ENOENT) {
			g_set_error(error,
				    G_FILE_ERROR,
				    g_file_error_from_errno(errno),
				    "failed to remove %s: %s",
				    self->state_path,
				    g_strerror(errno));
			return FALSE;
		}
		return TRUE;
	}

	dirname = g_path_get_dirname(self->state_path);
	if (g_mkdir_with_parents(dirname, 0755) < 0) {
		g_set_error(error,
			    G_FILE_ERROR,
			    g_file_error_from_errno(errno),
			    "failed to create %s: %s",
			    dirname,
			    g_strerror(errno));
		return FALSE;
	}

	keyfile = g_key_file_new();
	g_key_file_set_integer(keyfile, FU_PCRLOCK_STATE_GROUP, "Pending", pending_mask);
	g_key_file_set_integer(keyfile,
			       FU_PCRLOCK_STATE_GROUP,
			       "Deferred",
			       self->deferred_mask);
	data = g_key_file_to_data(keyfile, &data_size, error);
	if (data == NULL)
		return FALSE;
	return g_file_set_contents(self->state_path, data, data_size, error);
}

static gboolean
fu_pcrlock_plugin_load_state(FuPcrlockPlugin *self, GError **error)
{
	g_autoptr(GKeyFile) keyfile = NULL;
	gint deferred;
	gint pending;

	if (!g_file_test(self->state_path, G_FILE_TEST_EXISTS))
		return TRUE;

	keyfile = g_key_file_new();
	if (!g_key_file_load_from_file(keyfile, self->state_path, G_KEY_FILE_NONE, error))
		return FALSE;
	pending = g_key_file_get_integer(keyfile, FU_PCRLOCK_STATE_GROUP, "Pending", error);
	if (error != NULL && *error != NULL)
		return FALSE;
	deferred = g_key_file_get_integer(keyfile, FU_PCRLOCK_STATE_GROUP, "Deferred", error);
	if (error != NULL && *error != NULL)
		return FALSE;
	if (pending < 0 || deferred < 0 ||
	    ((guint)(pending | deferred) &
	     ~(FU_PCRLOCK_COMPONENT_FIRMWARE_CODE | FU_PCRLOCK_COMPONENT_SECURE_BOOT)) != 0) {
		g_set_error_literal(error,
				    FWUPD_ERROR,
				    FWUPD_ERROR_INVALID_DATA,
				    "invalid PCR-lock runtime state");
		return FALSE;
	}

	/* A daemon interruption makes the outcome uncertain; defer until reboot. */
	self->deferred_mask = (guint)(pending | deferred);
	return fu_pcrlock_plugin_save_state(self, error);
}

static gboolean
fu_pcrlock_plugin_run_helper(FuPcrlockPlugin *self,
			     const gchar *operation,
			     guint mask,
			     GError **error)
{
	g_autofree gchar *mask_str = g_strdup_printf("%u", mask);
	g_autofree gchar *stdout_buf = NULL;
	g_autofree gchar *stderr_buf = NULL;
	g_autoptr(GError) error_local = NULL;
	gint wait_status = 0;
	gchar *argv[] = {
		self->helper_path,
		(gchar *)operation,
		mask_str,
		NULL,
	};

	if (mask == FU_PCRLOCK_COMPONENT_NONE)
		return TRUE;
	if (!g_spawn_sync(NULL,
			  argv,
			  NULL,
			  G_SPAWN_DEFAULT,
			  NULL,
			  NULL,
			  &stdout_buf,
			  &stderr_buf,
			  &wait_status,
			  &error_local)) {
		g_set_error(error,
			    FWUPD_ERROR,
			    FWUPD_ERROR_INTERNAL,
			    "failed to execute PCR-lock helper: %s",
			    error_local->message);
		return FALSE;
	}
	if (!g_spawn_check_wait_status(wait_status, &error_local)) {
		g_set_error(error,
			    FWUPD_ERROR,
			    FWUPD_ERROR_INTERNAL,
			    "PCR-lock helper %s failed: %s%s%s",
			    operation,
			    error_local->message,
			    stderr_buf != NULL && stderr_buf[0] != '\0' ? ": " : "",
			    stderr_buf != NULL ? g_strstrip(stderr_buf) : "");
		return FALSE;
	}
	return TRUE;
}

static gboolean
fu_pcrlock_plugin_finish_device(FuPcrlockPlugin *self,
				const gchar *device_id,
				gboolean defer_until_reboot,
				GError **error)
{
	FuPcrlockTransaction *transaction = g_hash_table_lookup(self->transactions, device_id);
	guint preserve_mask;
	guint restore_mask;

	if (transaction == NULL)
		return TRUE;

	if (defer_until_reboot) {
		self->deferred_mask |= transaction->mask;
		g_hash_table_remove(self->transactions, device_id);
		return fu_pcrlock_plugin_save_state(self, error);
	}

	preserve_mask =
	    self->deferred_mask | fu_pcrlock_plugin_get_pending_mask_except(self, device_id);
	restore_mask = transaction->mask & ~preserve_mask;
	if (!fu_pcrlock_plugin_run_helper(self,
					  "restore",
					  restore_mask,
					  error)) {
		g_autoptr(GError) error_state = NULL;
		self->deferred_mask |= transaction->mask;
		g_hash_table_remove(self->transactions, device_id);
		if (!fu_pcrlock_plugin_save_state(self, &error_state))
			g_warning("failed to preserve uncertain PCR-lock state: %s",
				  error_state->message);
		return FALSE;
	}

	g_hash_table_remove(self->transactions, device_id);
	return fu_pcrlock_plugin_save_state(self, error);
}

static gboolean
fu_pcrlock_plugin_startup(FuPlugin *plugin, FuProgress *progress, GError **error)
{
	FuPcrlockPlugin *self = FU_PCRLOCK_PLUGIN(plugin);
	g_autoptr(GError) error_local = NULL;

	if (!fu_pcrlock_plugin_load_state(self, &error_local)) {
		self->state_error = g_strdup(error_local->message);
		g_warning("PCR-lock integration will fail closed: %s", self->state_error);
	}
	return TRUE;
}

static gboolean
fu_pcrlock_plugin_prepare(FuPlugin *plugin,
			  FuDevice *device,
			  FuProgress *progress,
			  FwupdInstallFlags flags,
			  GError **error)
{
	FuPcrlockPlugin *self = FU_PCRLOCK_PLUGIN(plugin);
	FuPcrlockTransaction *transaction;
	const gchar *device_id;
	guint mask = fu_pcrlock_plugin_device_mask(device);
	guint preserve_mask;

	if (mask == FU_PCRLOCK_COMPONENT_NONE)
		return TRUE;
	if (self->state_error != NULL) {
		g_set_error(error,
			    FWUPD_ERROR,
			    FWUPD_ERROR_INTERNAL,
			    "PCR-lock state is unavailable: %s",
			    self->state_error);
		return FALSE;
	}

	device_id = fu_device_get_id(device);
	if (device_id == NULL) {
		g_set_error_literal(error,
				    FWUPD_ERROR,
				    FWUPD_ERROR_INTERNAL,
				    "cannot prepare PCR-lock for a device without an ID");
		return FALSE;
	}
	if (g_hash_table_contains(self->transactions, device_id))
		return TRUE;

	preserve_mask = self->deferred_mask | fu_pcrlock_plugin_get_pending_mask(self);
	transaction = g_new0(FuPcrlockTransaction, 1);
	transaction->mask = mask;
	g_hash_table_insert(self->transactions, g_strdup(device_id), transaction);
	if (!fu_pcrlock_plugin_save_state(self, error)) {
		g_hash_table_remove(self->transactions, device_id);
		return FALSE;
	}
	if (!fu_pcrlock_plugin_run_helper(self, "prepare", mask, error)) {
		guint rollback_mask = mask & ~preserve_mask;
		g_autoptr(GError) error_restore = NULL;
		g_autoptr(GError) error_state = NULL;

		if (!fu_pcrlock_plugin_run_helper(self,
						  "restore",
						  rollback_mask,
						  &error_restore)) {
			self->deferred_mask |= mask;
			g_warning("failed to restore PCR-lock after preparation failure: %s",
				  error_restore->message);
		}
		g_hash_table_remove(self->transactions, device_id);
		if (!fu_pcrlock_plugin_save_state(self, &error_state))
			g_warning("failed to save PCR-lock state after preparation failure: %s",
				  error_state->message);
		return FALSE;
	}
	return TRUE;
}

static gboolean
fu_pcrlock_plugin_composite_peek_firmware(FuPlugin *plugin,
					  FuDevice *device,
					  FuFirmware *firmware,
					  FuProgress *progress,
					  FwupdInstallFlags flags,
					  GError **error)
{
	FuPcrlockPlugin *self = FU_PCRLOCK_PLUGIN(plugin);
	const gchar *device_id = fu_device_get_id(device);
	FuPcrlockTransaction *transaction;

	if (device_id == NULL)
		return TRUE;
	transaction = g_hash_table_lookup(self->transactions, device_id);
	if (transaction != NULL)
		transaction->write_started = TRUE;
	return TRUE;
}

static gboolean
fu_pcrlock_plugin_cleanup(FuPlugin *plugin,
			  FuDevice *device,
			  FuProgress *progress,
			  FwupdInstallFlags flags,
			  GError **error)
{
	FuPcrlockPlugin *self = FU_PCRLOCK_PLUGIN(plugin);
	const gchar *device_id = fu_device_get_id(device);
	FuPcrlockTransaction *transaction;
	FwupdUpdateState state;

	if (device_id == NULL)
		return TRUE;
	transaction = g_hash_table_lookup(self->transactions, device_id);
	if (transaction == NULL)
		return TRUE;

	state = fu_device_get_update_state(device);
	if (state == FWUPD_UPDATE_STATE_FAILED ||
	    state == FWUPD_UPDATE_STATE_FAILED_TRANSIENT) {
		return fu_pcrlock_plugin_finish_device(self,
						       device_id,
						       transaction->write_started,
						       error);
	}
	if (state == FWUPD_UPDATE_STATE_SUCCESS ||
	    state == FWUPD_UPDATE_STATE_NEEDS_REBOOT)
		return fu_pcrlock_plugin_finish_device(self, device_id, TRUE, error);
	return TRUE;
}

static FuDevice *
fu_pcrlock_plugin_find_device(GPtrArray *devices, const gchar *device_id)
{
	for (guint i = 0; i < devices->len; i++) {
		FuDevice *device = g_ptr_array_index(devices, i);
		if (g_strcmp0(fu_device_get_id(device), device_id) == 0)
			return device;
	}
	return NULL;
}

static gboolean
fu_pcrlock_plugin_composite_cleanup(FuPlugin *plugin, GPtrArray *devices, GError **error)
{
	FuPcrlockPlugin *self = FU_PCRLOCK_PLUGIN(plugin);
	g_autoptr(GPtrArray) device_ids = g_ptr_array_new_with_free_func(g_free);
	g_autoptr(GError) error_first = NULL;
	GHashTableIter iter;
	gpointer key;

	g_hash_table_iter_init(&iter, self->transactions);
	while (g_hash_table_iter_next(&iter, &key, NULL))
		g_ptr_array_add(device_ids, g_strdup(key));

	for (guint i = 0; i < device_ids->len; i++) {
		const gchar *device_id = g_ptr_array_index(device_ids, i);
		FuPcrlockTransaction *transaction =
		    g_hash_table_lookup(self->transactions, device_id);
		FuDevice *device = fu_pcrlock_plugin_find_device(devices, device_id);
		gboolean defer_until_reboot;
		g_autoptr(GError) error_local = NULL;

		if (transaction == NULL)
			continue;
		if (device == NULL) {
			defer_until_reboot = TRUE;
		} else {
			FwupdUpdateState state = fu_device_get_update_state(device);
			defer_until_reboot =
			    transaction->write_started ||
			    (state != FWUPD_UPDATE_STATE_FAILED &&
			     state != FWUPD_UPDATE_STATE_FAILED_TRANSIENT);
		}
		if (!fu_pcrlock_plugin_finish_device(self,
						     device_id,
						     defer_until_reboot,
						     &error_local) &&
		    error_first == NULL)
			error_first = g_steal_pointer(&error_local);
	}

	if (error_first != NULL) {
		g_propagate_error(error, g_steal_pointer(&error_first));
		return FALSE;
	}
	return TRUE;
}

void
fu_pcrlock_plugin_set_helper_path(FuPcrlockPlugin *self, const gchar *path)
{
	g_return_if_fail(FU_IS_PCRLOCK_PLUGIN(self));
	g_return_if_fail(path != NULL);
	g_free(self->helper_path);
	self->helper_path = g_strdup(path);
}

void
fu_pcrlock_plugin_set_state_path(FuPcrlockPlugin *self, const gchar *path)
{
	g_return_if_fail(FU_IS_PCRLOCK_PLUGIN(self));
	g_return_if_fail(path != NULL);
	g_free(self->state_path);
	self->state_path = g_strdup(path);
	g_clear_pointer(&self->state_error, g_free);
	self->deferred_mask = FU_PCRLOCK_COMPONENT_NONE;
	g_hash_table_remove_all(self->transactions);
}

static void
fu_pcrlock_plugin_init(FuPcrlockPlugin *self)
{
	self->transactions =
	    g_hash_table_new_full(g_str_hash,
				  g_str_equal,
				  g_free,
				  (GDestroyNotify)fu_pcrlock_transaction_free);
	self->helper_path = g_strdup(FU_PCRLOCK_HELPER_PATH);
	self->state_path = g_strdup(FU_PCRLOCK_STATE_PATH);
}

static void
fu_pcrlock_plugin_constructed(GObject *obj)
{
	FuPlugin *plugin = FU_PLUGIN(obj);
	const gchar *run_after[] = {
		"snap",
		"uefi_capsule",
		"uefi_db",
		"uefi_dbx",
		"uefi_kek",
		"uefi_pk",
	};

	for (guint i = 0; i < G_N_ELEMENTS(run_after); i++)
		fu_plugin_add_rule(plugin, FU_PLUGIN_RULE_RUN_AFTER, run_after[i]);
	G_OBJECT_CLASS(fu_pcrlock_plugin_parent_class)->constructed(obj);
}

static void
fu_pcrlock_plugin_finalize(GObject *obj)
{
	FuPcrlockPlugin *self = FU_PCRLOCK_PLUGIN(obj);
	g_hash_table_unref(self->transactions);
	g_free(self->helper_path);
	g_free(self->state_path);
	g_free(self->state_error);
	G_OBJECT_CLASS(fu_pcrlock_plugin_parent_class)->finalize(obj);
}

static void
fu_pcrlock_plugin_class_init(FuPcrlockPluginClass *klass)
{
	FuPluginClass *plugin_class = FU_PLUGIN_CLASS(klass);
	GObjectClass *object_class = G_OBJECT_CLASS(klass);

	object_class->constructed = fu_pcrlock_plugin_constructed;
	object_class->finalize = fu_pcrlock_plugin_finalize;
	plugin_class->startup = fu_pcrlock_plugin_startup;
	plugin_class->prepare = fu_pcrlock_plugin_prepare;
	plugin_class->cleanup = fu_pcrlock_plugin_cleanup;
	plugin_class->composite_cleanup = fu_pcrlock_plugin_composite_cleanup;
	plugin_class->composite_peek_firmware = fu_pcrlock_plugin_composite_peek_firmware;
}
