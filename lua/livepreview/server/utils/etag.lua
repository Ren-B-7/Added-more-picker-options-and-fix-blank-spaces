---@brief ETag module
--- To require this module, do
--- ```lua
--- local etag = require('livepreview.server.utils.etag')
--- ```

local M = {}

local plugin_path = require("livepreview.utils").get_plugin_path()
local template_path = vim.fs.joinpath(plugin_path, "lua/livepreview/template.lua")

--- Generate an ETag for a file
--- The Etag is generated based on the modification time of the file
--- @param file_path string: path to the file
--- @return string?: ETag
function M.generate(file_path)
	local etag
	local attr = vim.uv.fs_stat(file_path)
	local template_mtime
	if not attr then
		return nil
	end
	local modification_time = attr.mtime
	local template_stat = vim.uv.fs_stat(template_path)
	if not template_stat then
		template_mtime = { sec = 0, nsec = 0 }
	else
		template_mtime = template_stat.mtime
	end

	local function mtime_compare(mtime1, mtime2)
		if mtime1.sec > mtime2.sec then
			return true
		elseif mtime1.sec == mtime2.sec then
			return mtime1.nsec > mtime2.nsec
		else
			return false
		end
	end

	if mtime_compare(modification_time, template_mtime) then
		etag = modification_time.sec .. "." .. modification_time.nsec
	else
		etag = template_mtime.sec .. "." .. template_mtime.nsec
	end
	return etag
end

return M
