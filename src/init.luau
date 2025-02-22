--!strict
local RunService = game:GetService("RunService")
-- Services
-- Packages
local ServiceProxy = require("@wally/ServiceProxy")
local Maid = require("@wally/Maid")
local Queue = require("@wally/Queue")
local Signal = require("@wally/Signal")
-- Modules
-- Types
-- Constants
-- Variables
-- References
-- Private Functions
-- Class
-- Types
type Signal<V...> = Signal.Signal<V...>
type Queue<V> = Queue.Queue<V>
type Maid = Maid.Maid
type RateLimitHandler = {
	FullKey: string,
	Queue: Queue<(isAlive: boolean) -> ()>,
	MinuteRate: number,
	NextTick: number,
	GetNextTick: (self: RateLimitHandler) -> number,
}
type RateServiceImpl = {
	__index: RateServiceImpl,
	ScheduleAsync: <V>(self: RateService, key: string, minuteRate: number, callback: () -> V) -> V,
	Destroy: (self: RateService) -> (),
	new: () -> RateService,
	init: () -> () -> (),
}

export type RateService = typeof(setmetatable(
	{} :: {
		_Maid: Maid,
		_IsAlive: boolean,
		_Handlers: { [string]: RateLimitHandler },
	},
	{} :: RateServiceImpl
))

-- Class
local CurrentRateService: RateService? = nil :: any

local RateService = {} :: RateServiceImpl
RateService.__index = RateService

function RateService:Destroy()
	if not self._IsAlive then
		return
	end
	self._IsAlive = false
	if CurrentRateService == self then
		CurrentRateService = nil :: any
	end
	for k, handler in pairs(self._Handlers) do
		local t = handler.Queue:Get()
		while t do
			local s, m = pcall(function()
				t(false)
			end)
			if not s then
				warn(m)
			end
			t = handler.Queue:Get()
		end
	end
	table.clear(self._Handlers)
	self._Maid:Destroy()
	setmetatable(self :: any, nil)
	table.clear(self :: any)
end

function RateService:ScheduleAsync<V>(key: string, minuteRate: number, callback: () -> V): V
	assert(self._IsAlive, "RateService wasn't initialized / was destroyed")
	local fullKey = `{key}:{minuteRate}`
	local handler: RateLimitHandler = self._Handlers[fullKey]
		or {
			FullKey = fullKey,
			Queue = (function(): Queue<(isAlive: boolean) -> ()>
				local q = Queue.new()
				q.IsSorted = true
				return q
			end)(),
			MinuteRate = minuteRate,
			NextTick = tick(),
			GetNextTick = function(selfHandler: RateLimitHandler): number
				return selfHandler.NextTick + 60 / selfHandler.MinuteRate
			end,
		}

	local onCall: Signal.Signal<boolean> = Signal.new()

	local fireResult: boolean? = nil
	handler.Queue:Add(function(isAlive: boolean)
		fireResult = isAlive
		onCall:Fire(isAlive)
	end, tick())

	if self._IsAlive then
		self._Handlers[fullKey] = handler
	end

	local isAlive = if fireResult == nil then onCall:Wait() else fireResult

	if isAlive then
		return callback()
	else
		error(`RateService was destroyed`)
	end
end

function RateService.new(): RateService
	local maid = Maid.new()
	local self = setmetatable({
		_IsAlive = true,
		_Maid = maid,
		_Handlers = {},
	}, RateService)

	self._Maid:GiveTask(RunService.Heartbeat:Connect(function(dt: number)
		local t = tick()
		for k, handler in pairs(self._Handlers) do
			if handler.NextTick <= t then
				local trigger = handler.Queue:Get()
				if trigger then
					handler.NextTick = handler:GetNextTick()
					trigger()
				else
					self._Handlers[k] = nil
				end
			end
		end
	end))

	if CurrentRateService ~= nil then
		CurrentRateService:Destroy()
		CurrentRateService = nil
	end
	CurrentRateService = self

	return self
end

function RateService.init(): () -> ()
	print(`booting {script.Name}`)
	local maid = Maid.new()
	maid:GiveTask(RateService.new())
	return function()
		maid:Destroy()
	end
end

return ServiceProxy(function(): RateService
	return (CurrentRateService or RateService) :: any
end)
