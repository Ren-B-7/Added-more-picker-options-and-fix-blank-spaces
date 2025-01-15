---@brief HTTP handler module for server in live-preview.nvim
--- To require this module, do
--- ```lua
--- local handler = require('livepreview.server.handler')
--- ```

local websocket = require("livepreview.server.websocket")
local read_file = require("livepreview.utils").async_read_file
local supported_filetype = require("livepreview.utils").supported_filetype
local toHTML = require("livepreview.template").toHTML
local handle_body = require("livepreview.template").handle_body
local get_content_type = require("livepreview.server.utils.content_type").get
local generate_etag = require("livepreview.server.utils.etag").generate

local M = {}

--- Send an HTTP response
--- @param client uv_tcp_t: client connection
--- @param status string: for example "200 OK", "404 Not Found", etc.
--- @param content_type string: MIME type of the response
--- @param body string: body of the response
--- @param headers table|nil: (optional) additional headers to include in the response
function M.send_http_response(client, status, content_type, body, headers)
	local response = "HTTP/1.1 "
		.. status
		.. "\r\n"
		.. "Content-Type: "
		.. content_type
		.. "\r\n"
		.. "Content-Length: "
		.. #body
		.. "\r\n"
		.. "Connection: close\r\n"

	if headers then
		for k, v in pairs(headers) do
			response = response .. k .. ": " .. v .. "\r\n"
		end
	end

	response = response .. "\r\n" .. body

	client:write(response)
end

--- Handle an HTTP request
--- If the request is a websocket upgrade request, it will call websocket handshake
--- Otherwise, if it is a GET request, return the path from it
---@param request string: HTTP request
---@return {path: string, if_none_match: string} | nil : path to the file and If-None-Match header
function M.request(client, request)
	if request:match("Upgrade: websocket") then
		websocket.handshake(client, request)
		return
	end
	local path = request:match("GET ([^%s]+) HTTP/1.1")
	path = path and path:gsub("%%20", " ") or "/"

	local if_none_match = request:match("If%-None%-Match: ([^\r\n]+)")

	return {
		path = path,
		if_none_match = if_none_match,
	}
end

--- Serve a file to the client
--- @param client uv_tcp_t: client connection
--- @param file_path string: path to the file
function M.serve_file(client, file_path, if_none_match)
	read_file(file_path, function(_, body)
		if not body then
			M.send_http_response(client, "404 Not Found", "text/plain", "404 Not Found")
			return
		end

		local etag = generate_etag(file_path)

		if if_none_match and if_none_match == etag then
			M.send_http_response(client, "304 Not Modified", get_content_type(file_path) or "", "", {
				["ETag"] = etag,
			})
			return
		end

		local filetype = supported_filetype(file_path)
		if filetype then
			if filetype ~= "html" then
				body = toHTML(body, filetype)
			else
				body = handle_body(body)
			end
		end

		M.send_http_response(client, "200 OK", get_content_type(file_path) or "", body, {
			["ETag"] = etag,
		})
	end)
end

--- Handle a client connection, read the request and send a response
---@param client uv_tcp_t: client connection
---@param callback function(): callback function to handle the result
---    - `err`: Error message, if any (nil if no error)
---    - `data`: Request from the client
---@return string: request from the client
function M.client(client, callback)
	local buffer = ""

	client:read_start(function(err, chunk)
		if err then
			client:close()
			callback(err, nil)
		end

		if chunk then
			buffer = buffer .. chunk
			if buffer:match("\r\n\r\n$") then
				client:read_stop()
				callback(nil, buffer)
			end
		else
			client:close()
		end
	end)
end

return M
