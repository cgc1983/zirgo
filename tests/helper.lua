#!/usr/bin/env luvit

local spawn = require('childprocess').spawn
local fs = require('fs')
local path = require('path')

local misc = require('/util/misc')
local constants = require('constants')
local vutils = require('virgo_utils')

function start_agent()
  local config_path = path.join(TEST_DIR, 'monitoring-agent-localhost.cfg')
  local args = {
    '-o', '-d', '-n',
    '-s', TEST_DIR,
    '-z', virgo.loaded_zip_path,
    '-c', config_path
  }

  config = get_static('/static/tests/monitoring-agent-localhost.cfg')
  fs.writeFileSync(config_path, config)

  local agent = spawn(process.execPath, args)

  agent.stderr:on('data', function(d)
    process.stderr:write(d)
  end)
  agent.stdout:on('data', function(d)
    process.stdout:write(d)
  end)
  return agent
end

local child

local function start_server(callback)
  local data = ''
  callback = misc.fireOnce(callback)
  print('starting server')
  child = spawn('luvit', {"tests/server.lua"})
  child.stderr:on('data', function(d)
    p(d)
    callback(d)
  end)

  child.stdout:on('data', function(chunk)
    p(chunk)
    data = data .. chunk
    if data:find('TLS fixture server listening on port 50061') then
      callback()
    end
  end)
  return child
end

local function stop_server(child)
  if not child then return end
  pcall(function()
    child:kill(constants.SIGUSR1) -- USR1
  end)
end

process:on('exit', function()
  stop_server(child)
end)

process:on("error", function(e)
  stop_server(child)
end)

-- This will skip all the functions in an export list but still be able to call them individually
local function skip_all(exports, reason)
  for i,v in pairs(exports) do
    p("Setting a skip " .. i .. " for " .. reason)
    exports[i] = function(test, asserts)
      test.skip("Skipping " .. i .. " for " .. reason)
    end
  end
  return exports
end

if not virgo then
  -- parse argv and stuff here
  return
end

local exports = {}
exports.runner = runner
exports.start_server = start_server
exports.stop_server = stop_server
exports.skip_all = skip_all
exports.start_agent = start_agent
return exports