host_machine.system() == 'linux' or subdir_done()

cargs = ['-DG_LOG_DOMAIN="FuPluginPcrlock"']
plugins += {meson.current_source_dir().split('/')[-1]: true}

plugin_builtin_pcrlock = static_library(
  'fu_plugin_pcrlock',
  sources: [
    'fu-pcrlock-plugin.c',
  ],
  include_directories: plugin_incdirs,
  link_with: plugin_libs,
  c_args: cargs,
  dependencies: plugin_deps,
)
plugin_builtins += plugin_builtin_pcrlock

if get_option('tests')
  e = executable(
    'pcrlock-self-test',
    sources: [
      'fu-self-test.c',
    ],
    include_directories: plugin_incdirs,
    dependencies: plugin_deps,
    link_with: [
      plugin_libs,
      plugin_builtin_pcrlock,
    ],
    install: true,
    install_rpath: libdir_pkg,
    install_tag: 'tests',
    install_dir: installed_test_bindir,
    c_args: cargs,
  )
  test('pcrlock-self-test', e)
endif
