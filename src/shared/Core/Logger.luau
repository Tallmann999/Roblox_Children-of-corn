--!strict

local Logger = {}
Logger.__index = Logger

function Logger.new(scope: string, debugEnabled: boolean?)
	return setmetatable({
		_scope = scope,
		_debug = debugEnabled == true,
	}, Logger)
end

function Logger:Info(...: any)
	print(string.format("[%s]", self._scope), ...)
end

function Logger:Warn(...: any)
	warn(string.format("[%s]", self._scope), ...)
end

function Logger:Debug(...: any)
	if self._debug then
		print(string.format("[%s][DEBUG]", self._scope), ...)
	end
end

return Logger
