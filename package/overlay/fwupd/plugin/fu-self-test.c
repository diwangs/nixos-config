/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#include "config.h"

#include "fu-context-private.h"
#include "fu-pcrlock-plugin.h"
#include "fu-plugin-private.h"

typedef struct {
	FuContext *ctx;
	FuPlugin *plugin;
	FuProgress *progress;
	FuTemporaryDirectory *tmpdir;
	gchar *state_path;
} FuPcrlockFixture;

static void
fu_pcrlock_fixture_setup(FuPcrlockFixture *fixture, gconstpointer user_data)
{
	const gchar *helper = g_find_program_in_path("true");
	g_autoptr(GError) error = NULL;

	fixture->ctx = fu_context_new();
	fixture->plugin = fu_plugin_new_from_gtype(FU_TYPE_PCRLOCK_PLUGIN, fixture->ctx);
	fixture->progress = fu_progress_new(G_STRLOC);
	fixture->tmpdir = fu_temporary_directory_new("pcrlock", &error);
	g_assert_no_error(error);
	g_assert_nonnull(helper);
	g_assert_nonnull(fixture->tmpdir);
	fixture->state_path =
	    g_build_filename(fu_temporary_directory_get_path(fixture->tmpdir), "state.ini", NULL);
	fu_pcrlock_plugin_set_helper_path(FU_PCRLOCK_PLUGIN(fixture->plugin), helper);
	fu_pcrlock_plugin_set_state_path(FU_PCRLOCK_PLUGIN(fixture->plugin),
					 fixture->state_path);
}

static void
fu_pcrlock_fixture_teardown(FuPcrlockFixture *fixture, gconstpointer user_data)
{
	g_clear_object(&fixture->plugin);
	g_clear_object(&fixture->progress);
	g_clear_object(&fixture->ctx);
	g_clear_object(&fixture->tmpdir);
	g_clear_pointer(&fixture->state_path, g_free);
}

static FuDevice *
fu_pcrlock_test_device_new(const gchar *plugin, const gchar *id)
{
	FuDevice *device = fu_device_new(NULL);
	fu_device_set_plugin(device, plugin);
	fu_device_set_id(device, id);
	return device;
}

static FuDevice *
fu_pcrlock_test_capsule_new(gboolean is_system_firmware, const gchar *id)
{
	FuDevice *device = fu_pcrlock_test_device_new("uefi_capsule", id);

	if (is_system_firmware)
		fu_device_add_private_flag(device, FU_DEVICE_PRIVATE_FLAG_HOST_FIRMWARE);
	return device;
}

static void
fu_pcrlock_classification_func(void)
{
	const gchar *secure_boot_plugins[] = {
		"uefi_db",
		"uefi_dbx",
		"uefi_kek",
		"uefi_pk",
	};
	g_autoptr(FuDevice) system =
	    fu_pcrlock_test_capsule_new(TRUE, "system");
	g_autoptr(FuDevice) device =
	    fu_pcrlock_test_capsule_new(FALSE, "device");
	g_autoptr(FuDevice) unrelated = fu_pcrlock_test_device_new("nvme", "nvme");

	g_assert_cmpuint(fu_pcrlock_plugin_device_mask(system),
			 ==,
			 FU_PCRLOCK_COMPONENT_FIRMWARE_CODE);
	g_assert_cmpuint(fu_pcrlock_plugin_device_mask(device),
			 ==,
			 FU_PCRLOCK_COMPONENT_NONE);
	g_assert_cmpuint(fu_pcrlock_plugin_device_mask(unrelated),
			 ==,
			 FU_PCRLOCK_COMPONENT_NONE);
	for (guint i = 0; i < G_N_ELEMENTS(secure_boot_plugins); i++) {
		g_autoptr(FuDevice) secure_boot =
		    fu_pcrlock_test_device_new(secure_boot_plugins[i], secure_boot_plugins[i]);
		g_assert_cmpuint(fu_pcrlock_plugin_device_mask(secure_boot),
				 ==,
				 FU_PCRLOCK_COMPONENT_SECURE_BOOT);
	}
}

static void
fu_pcrlock_failure_before_write_func(FuPcrlockFixture *fixture, gconstpointer user_data)
{
	g_autoptr(FuDevice) device = fu_pcrlock_test_device_new("uefi_dbx", "dbx");
	g_autoptr(GPtrArray) devices =
	    g_ptr_array_new_with_free_func((GDestroyNotify)g_object_unref);
	g_autoptr(GError) error = NULL;

	g_assert_true(fu_plugin_runner_prepare(fixture->plugin,
					      device,
					      fixture->progress,
					      FWUPD_INSTALL_FLAG_NONE,
					      &error));
	g_assert_no_error(error);
	g_assert_cmpuint(
	    fu_pcrlock_plugin_get_pending_mask(FU_PCRLOCK_PLUGIN(fixture->plugin)),
	    ==,
	    FU_PCRLOCK_COMPONENT_SECURE_BOOT);

	fu_device_set_update_state(device, FWUPD_UPDATE_STATE_FAILED);
	g_ptr_array_add(devices, g_object_ref(device));
	g_assert_true(fu_plugin_runner_composite_cleanup(fixture->plugin, devices, &error));
	g_assert_no_error(error);
	g_assert_cmpuint(
	    fu_pcrlock_plugin_get_pending_mask(FU_PCRLOCK_PLUGIN(fixture->plugin)),
	    ==,
	    FU_PCRLOCK_COMPONENT_NONE);
	g_assert_cmpuint(
	    fu_pcrlock_plugin_get_deferred_mask(FU_PCRLOCK_PLUGIN(fixture->plugin)),
	    ==,
	    FU_PCRLOCK_COMPONENT_NONE);
}

static void
fu_pcrlock_failure_after_write_func(FuPcrlockFixture *fixture, gconstpointer user_data)
{
	g_autoptr(FuDevice) device = fu_pcrlock_test_device_new("uefi_dbx", "dbx");
	g_autoptr(FuFirmware) firmware = fu_firmware_new();
	g_autoptr(GPtrArray) devices =
	    g_ptr_array_new_with_free_func((GDestroyNotify)g_object_unref);
	g_autoptr(GError) error = NULL;

	g_assert_true(fu_plugin_runner_prepare(fixture->plugin,
					      device,
					      fixture->progress,
					      FWUPD_INSTALL_FLAG_NONE,
					      &error));
	g_assert_no_error(error);
	g_assert_true(fu_plugin_runner_composite_peek_firmware(fixture->plugin,
							       device,
							       firmware,
							       fixture->progress,
							       FWUPD_INSTALL_FLAG_NONE,
							       &error));
	g_assert_no_error(error);
	fu_device_set_update_state(device, FWUPD_UPDATE_STATE_FAILED);
	g_ptr_array_add(devices, g_object_ref(device));
	g_assert_true(fu_plugin_runner_composite_cleanup(fixture->plugin, devices, &error));
	g_assert_no_error(error);
	g_assert_cmpuint(
	    fu_pcrlock_plugin_get_pending_mask(FU_PCRLOCK_PLUGIN(fixture->plugin)),
	    ==,
	    FU_PCRLOCK_COMPONENT_NONE);
	g_assert_cmpuint(
	    fu_pcrlock_plugin_get_deferred_mask(FU_PCRLOCK_PLUGIN(fixture->plugin)),
	    ==,
	    FU_PCRLOCK_COMPONENT_SECURE_BOOT);
}

static void
fu_pcrlock_helper_failure_func(FuPcrlockFixture *fixture, gconstpointer user_data)
{
	const gchar *helper = g_find_program_in_path("false");
	g_autoptr(FuDevice) device = fu_pcrlock_test_device_new("uefi_dbx", "dbx");
	g_autoptr(GError) error = NULL;

	g_assert_nonnull(helper);
	fu_pcrlock_plugin_set_helper_path(FU_PCRLOCK_PLUGIN(fixture->plugin), helper);
	g_test_expect_message("FuPluginPcrlock",
			      G_LOG_LEVEL_WARNING,
			      "failed to restore PCR-lock after preparation failure: *");
	g_assert_false(fu_plugin_runner_prepare(fixture->plugin,
					       device,
					       fixture->progress,
					       FWUPD_INSTALL_FLAG_NONE,
					       &error));
	g_test_assert_expected_messages();
	g_assert_error(error, FWUPD_ERROR, FWUPD_ERROR_INTERNAL);
	g_assert_cmpuint(
	    fu_pcrlock_plugin_get_pending_mask(FU_PCRLOCK_PLUGIN(fixture->plugin)),
	    ==,
	    FU_PCRLOCK_COMPONENT_NONE);
	g_assert_cmpuint(
	    fu_pcrlock_plugin_get_deferred_mask(FU_PCRLOCK_PLUGIN(fixture->plugin)),
	    ==,
	    FU_PCRLOCK_COMPONENT_SECURE_BOOT);
}

static void
fu_pcrlock_interrupted_state_func(FuPcrlockFixture *fixture, gconstpointer user_data)
{
	const gchar state[] = "[Pcrlock]\nPending=1\nDeferred=2\n";
	g_autoptr(GError) error = NULL;

	g_assert_true(g_file_set_contents(fixture->state_path, state, -1, &error));
	g_assert_no_error(error);
	g_assert_true(
	    fu_plugin_runner_startup(fixture->plugin, fixture->progress, &error));
	g_assert_no_error(error);
	g_assert_cmpuint(
	    fu_pcrlock_plugin_get_deferred_mask(FU_PCRLOCK_PLUGIN(fixture->plugin)),
	    ==,
	    FU_PCRLOCK_COMPONENT_FIRMWARE_CODE | FU_PCRLOCK_COMPONENT_SECURE_BOOT);
	g_assert_cmpuint(
	    fu_pcrlock_plugin_get_pending_mask(FU_PCRLOCK_PLUGIN(fixture->plugin)),
	    ==,
	    FU_PCRLOCK_COMPONENT_NONE);
}

int
main(int argc, char **argv)
{
	g_test_init(&argc, &argv, NULL);
	g_test_add_func("/fwupd/pcrlock/classification", fu_pcrlock_classification_func);
	g_test_add("/fwupd/pcrlock/failure-before-write",
		   FuPcrlockFixture,
		   NULL,
		   fu_pcrlock_fixture_setup,
		   fu_pcrlock_failure_before_write_func,
		   fu_pcrlock_fixture_teardown);
	g_test_add("/fwupd/pcrlock/failure-after-write",
		   FuPcrlockFixture,
		   NULL,
		   fu_pcrlock_fixture_setup,
		   fu_pcrlock_failure_after_write_func,
		   fu_pcrlock_fixture_teardown);
	g_test_add("/fwupd/pcrlock/helper-failure",
		   FuPcrlockFixture,
		   NULL,
		   fu_pcrlock_fixture_setup,
		   fu_pcrlock_helper_failure_func,
		   fu_pcrlock_fixture_teardown);
	g_test_add("/fwupd/pcrlock/interrupted-state",
		   FuPcrlockFixture,
		   NULL,
		   fu_pcrlock_fixture_setup,
		   fu_pcrlock_interrupted_state_func,
		   fu_pcrlock_fixture_teardown);
	return g_test_run();
}
