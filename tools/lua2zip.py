#!/usr/bin/env python
#
#

import sys
import os
from bundle import generate_bundle_map
from zipfile import ZipFile, ZIP_DEFLATED

lib_lua = os.path.join('lib', 'lua')
async_lua = os.path.join('lua_modules', 'async')
bourbon_lua = os.path.join('lua_modules', 'bourbon')
options_lua = os.path.join('lua_modules', 'options')
traceroute_lua = os.path.join('lua_modules', 'traceroute')
line_emitter_lua = os.path.join('lua_modules', 'line-emitter')
rackspace_monitoring_client_lua = os.path.join('lua_modules', 'luvit-rackspace-monitoring-client')
luvit_keystone_client_lua = os.path.join('lua_modules', 'luvit-keystone-client')
luvit_lua = os.path.join('deps', 'luvit', 'lib', 'luvit')
monitoring_lua = os.path.join('agents', 'monitoring', 'default')
collector_lua = os.path.join('agents', 'monitoring', 'collector')
monitoring_tests = os.path.join('agents', 'monitoring', 'tests')

modules = {
  async_lua:
    generate_bundle_map('modules/async', 'lua_modules/async'),
  bourbon_lua:
    generate_bundle_map('modules/bourbon', 'lua_modules/bourbon'),
  options_lua:
    generate_bundle_map('modules/options', 'lua_modules/options'),
  traceroute_lua:
    generate_bundle_map('modules/traceroute', 'lua_modules/traceroute'),
  line_emitter_lua:
    generate_bundle_map('modules/line-emitter', 'lua_modules/line-emitter'),
  luvit_keystone_client_lua:
    generate_bundle_map('modules/keystone', 'lua_modules/luvit-keystone-client'),
  rackspace_monitoring_client_lua:
    generate_bundle_map('modules/rackspace-monitoring', 'lua_modules/luvit-rackspace-monitoring-client'),
  lib_lua:
    generate_bundle_map('', 'lib/lua', True),
  luvit_lua:
    generate_bundle_map('', 'deps/luvit/lib/luvit', True),
  monitoring_lua:
    generate_bundle_map('modules/monitoring/default', 'agents/monitoring/default'),
  collector_lua:
    generate_bundle_map('modules/monitoring/collector', 'agents/monitoring/collector'),
  monitoring_tests:
    generate_bundle_map('modules/monitoring/tests', 'agents/monitoring/tests'),
}

target = sys.argv[1]
sources = sys.argv[2:]

z = ZipFile(target, 'w', ZIP_DEFLATED)
for source in sources:
  if os.path.isdir(source):
    if modules.has_key(source):
      for mod_file in modules[source]:
        z.write(mod_file['os_filename'], mod_file['bundle_filename'])
  else:
    z.write(source, os.path.basename(source))
z.close()
