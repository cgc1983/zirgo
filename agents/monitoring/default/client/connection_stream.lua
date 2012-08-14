--[[
Copyright 2012 Rackspace

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]

local Emitter = require('core').Emitter
local math = require('math')
local timer = require('timer')
local fmt = require('string').format

local async = require('async')

local Scheduler = require('../schedule').Scheduler
local AgentClient = require('./client').AgentClient
local ConnectionMessages = require('./connection_messages').ConnectionMessages
local logging = require('logging')
local consts = require('../util/constants')
local misc = require('../util/misc')
local vtime = require('virgo-time')

local ConnectionStream = Emitter:extend()
function ConnectionStream:initialize(id, token, options)
  self._id = id
  self._token = token
  self._clients = {}
  self._unauthedClients = {}
  self._delays = {}
  self._messages = ConnectionMessages:new(self)
  self._activeTimeSyncClient = nil
  self._options = options or {}
end

--[[
Create and establish a connection to the multiple endpoints.

addresses - An Array of ip:port pairs
callback - Callback called with (err) when all the connections have been
established.
--]]
function ConnectionStream:createConnections(addresses, callback)
  async.series({
    function(callback)
      self._scheduler = Scheduler:new('scheduler.state', {}, callback)
      self._scheduler:on('check', function(check, checkResult)
        self:_sendMetrics(check, checkResult)
      end)
    end,
    function(callback)
      self._scheduler:start()
      callback()
    end,
    -- connect
    function(callback)
      async.forEach(addresses, function(address, callback)
        local split, client, options
        split = misc.splitAddress(address)
        options = misc.merge({
          host = split[1],
          port = split[2],
          datacenter = address
        }, self._options)
        self:createConnection(options, callback)
      end)
    end
  }, callback)
end

function ConnectionStream:_sendMetrics(check, checkResults)
  local client = self:getClient()
  if client then
    client.protocol:request('check_metrics.post', check, checkResults)
  end
end

function ConnectionStream:_setDelay(datacenter)
  local maxDelay = consts.DATACENTER_MAX_DELAY
  local jitter = consts.DATACENTER_MAX_DELAY_JITTER
  local previousDelay = self._delays[datacenter]
  local delay

  if previousDelay == nil then
    self._delays[datacenter] = 0
    previousDelay = 0
  end

  delay = math.min(previousDelay, maxDelay) + (jitter * math.random())
  self._delays[datacenter] = delay

  return delay
end

--[[
Retry a connection to the endpoint.

options - datacenter, host, port
  datacenter - Datacenter name / host alias.
  host - Hostname.
  port - Port.
callback - Callback called with (err)
]]--
function ConnectionStream:reconnect(options, callback)
  local datacenter = options.datacenter
  local delay = self:_setDelay(datacenter)

  logging.infof('%s:%d -> Retrying connection in %dms', options.host, options.port, delay)
  timer.setTimeout(delay, function()
    self:createConnection(options, callback)
  end)
end

function ConnectionStream:getClient()
  local client
  local latency
  local min_latency = 2147483647
  for k, v in pairs(self._clients) do
    latency = self._clients[k]:getLatency()
    if latency == nil then
      client = self._clients[k]
    elseif min_latency > latency then
      client = self._clients[k]
      min_latency = latency
    end
  end
  return client
end

function ConnectionStream:_attachTimeSyncEvent(client)
  if not client then
    self._activeTimeSyncClient = nil
    return
  end
  if self._activeTimeSyncClient then
    -- client already attached
    return
  end
  self._activeTimeSyncClient = client
  client:on('time_sync', function(timeObj)
    logging.info('Syncing time')
    vtime.timesync(timeObj.agent_send_timestamp, timeObj.server_receive_timestamp,
                   timeObj.server_response_timestamp, timeObj.agent_recv_timestamp)
  end)
end

--[[
Move an unauthenticated client to the list of clients that have been authenticated.
client - the client.
]]--
function ConnectionStream:_promoteClient(client)
  local datacenter = client:getDatacenter()
  client:log(logging.INFO, fmt('Connection has been authenticated to %s', datacenter))
  self._clients[datacenter] = client
  self._unauthedClients[datacenter] = nil
  self:_attachTimeSyncEvent(client)
  self:emit('promote')
end

--[[
Create and establish a connection to the endpoint.

datacenter - Datacenter name / host alias.
host - Hostname.
port - Port.
callback - Callback called with (err)
]]--
function ConnectionStream:createConnection(options, callback)
  local opts = misc.merge({
    id = self._id,
    token = self._token,
    timeout = consts.CONNECT_TIMEOUT
  }, options)

  local client = AgentClient:new(opts, self._scheduler)
  client:on('error', function(errorMessage)
    local err = {}
    err.host = opts.host
    err.port = opts.port
    err.datacenter = opts.datacenter
    err.message = errorMessage

    client:destroy()
    self:reconnect(opts, callback)
    if err then
      self:emit('error', err)
    end
  end)

  client:on('timeout', function()
    logging.debugf('%s:%d -> Client Timeout', opts.host, opts.port)
    client:destroy()
    self:reconnect(opts, callback)
  end)

  client:on('end', function()
    self:emit('client_end', client)

    -- Find a new client to handle time sync
    if self._activeTimeSyncClient == client then
      self._attachTimeSyncEvent(self:getClient())
    end

    logging.debugf('%s:%d -> Remote endpoint closed the connection', opts.host, opts.port)
    client:destroy()
    self:reconnect(opts, callback)
  end)

  client:on('handshake_success', function(data)
    self:_promoteClient(client)
    self._delays[options.datacenter] = 0
    client:startHeartbeatInterval()
    self._messages:emit('handshake_success', client, data)
  end)

  client:on('message', function(msg)
    self._messages:emit('message', client, msg)
  end)

  client:connect(function(err)
    if err then
      client:destroy()
      self:reconnect(opts, callback)
      callback(err)
      return
    end

    client.datacenter = datacenter
    self._unauthedClients[datacenter] = client

    callback();
  end)

  return client
end

local exports = {}
exports.ConnectionStream = ConnectionStream
return exports
