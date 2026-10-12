--!strict
-- macOS clipboard image -> SSH upload -> paste the server path into the
-- originating remote pane. The Tern display name must already be an ssh target.

local EXT: { [string]: boolean } = { png = true, jpg = true, jpeg = true, gif = true, webp = true }
local FILE_URL = [[try
POSIX path of (the clipboard as «class furl»)
on error
""
end try]]

local busy = false

local function log(message: string)
	tern.log.warn(message)
end

local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

local function macos(): boolean
	local ok, os_name = pcall(function()
		return tern.runtime.os
	end)
	return ok and os_name == "macos"
end

local function toast(cx: any, level: ToastLevel, text: string, sub: string?)
	if cx then
		cx:toast(level, text, sub)
	end
end

local function image_ext(path: string): boolean
	local ext = string.match(path, "%.([%w]+)$")
	return ext ~= nil and EXT[string.lower(ext)] == true
end

local function local_image(path: string): boolean
	if path == "" or string.sub(path, 1, 1) ~= "/" or not image_ext(path) then
		return false
	end
	local ok, exists = pcall(tern.fs.exists, path)
	return ok and exists == true
end

local function normalize(text: string): string
	local path = trim(text)
	if string.sub(path, 1, 7) == "file://" then
		path = string.gsub(string.sub(path, 8), "%%(%x%x)", function(hex)
			return string.char(tonumber(hex, 16) or 0)
		end)
	end
	return path
end

local function basename(path: string): string
	return string.match(path, "([^/]+)$") or "paste.png"
end

local function ssh_target(host: any): string
	local name = host.name
	if type(name) == "string" and name ~= "" and string.find(name, "%s") == nil and string.find(name, "@", 1, true) == nil then
		if string.match(name, "^[%w_][%w_%.%-]*$") then
			return name
		end
	end
	local address = host.address
	if type(address) == "string" and string.match(address, "^[%w_.%-]+@[%w_.%-]+$") then
		return address
	end
	if type(name) == "string" and string.match(name, "^[%w_.%-]+@[%w_.%-]+$") then
		return name
	end
	return ""
end

local function focused_id(cx: any): number?
	local ok, id = pcall(function()
		return cx.session:focused()
	end)
	if ok and type(id) == "number" then
		return id
	end
	return nil
end

local function host_owning(cx: any, pane_id: number): any?
	local ok, listed = pcall(function()
		return cx.hosts:list()
	end)
	if not ok or type(listed) ~= "table" then
		return nil
	end
	for _, host in listed do
		if type(host) == "table" and type(host.panes) == "table" then
			for _, member in host.panes do
				if member == pane_id then
					return host
				end
			end
		end
	end
	return nil
end

local function is_remote(host: any): boolean
	return type(host) == "table" and host.kind == "remote"
end

local function destination(cx: any): (any?, number?)
	local pane_id = focused_id(cx)
	local host = if pane_id ~= nil then host_owning(cx, pane_id) else nil
	if not is_remote(host) then
		return nil, pane_id
	end
	return host, pane_id
end

local function paste_server_path(cx: any, host: any, pane_id: number, abs: string)
	local ok, err = pcall(function()
		local owner = host_owning(cx, pane_id)
		local pane = cx.session:pane(pane_id)
		if not is_remote(owner) or owner.id ~= host.id or owner.address ~= host.address
			or owner.state ~= "connected" or pane == nil or pane.exited ~= nil then
			error("The originating remote pane is no longer available")
		end
		-- WindowCx:run types into this captured pane; only an explicit \r submits.
		cx:run(pane_id, abs)
	end)
	busy = false
	if not ok then
		log("paste failed " .. tostring(err))
		toast(cx, "error", "Uploaded, but paste failed", abs .. " — " .. tostring(err))
		return
	end
	log("inserted " .. abs)
	toast(cx, "success", "Pasted", abs)
end

local function deliver(cx: any, host: any, local_path: string, pane_id: number)
	if busy then
		toast(cx, "info", "Busy")
		return
	end
	local target = ssh_target(host)
	if target == "" then
		toast(cx, "error", "No host")
		return
	end
	busy = true
	local name = string.gsub(string.format("paste-%d-%s", math.floor(tern.now()), basename(local_path)), "[^%w%._%-]", "_")
	local remote_rel = ".omp/image-inbox/" .. name
	log("upload " .. local_path .. " -> " .. target .. ":" .. remote_rel)
	toast(cx, "info", "Transferring")
	local mkdir = 'mkdir -p "$HOME/.omp/image-inbox" && printf %s "$HOME/' .. remote_rel .. '"'
	tern.process.run({ "ssh", "-o", "BatchMode=yes", target, mkdir }, { timeout_ms = 20000 }, function(made, cx2)
		local live = cx2 or cx
		if made.status ~= 0 or trim(made.stdout or "") == "" then
			busy = false
			log("inbox failed " .. trim(made.stderr or ""))
			toast(live, "error", "Inbox failed", trim(made.stderr or ""))
			return
		end
		local abs = trim(made.stdout)
		tern.process.run({ "scp", "-q", "-o", "BatchMode=yes", local_path, target .. ":" .. remote_rel }, { timeout_ms = 30000 }, function(sent, cx3)
			local live3 = cx3 or live
			if sent.status ~= 0 then
				busy = false
				log("transfer failed " .. trim(sent.stderr or ""))
				toast(live3, "error", "Transfer failed", trim(sent.stderr or ""))
				return
			end
			log("uploaded " .. abs)
			paste_server_path(live3, host, pane_id, abs)
		end)
	end)
end

local function read_image(cx: any, done: (any, string) -> ())
	tern.process.run({ "osascript", "-e", FILE_URL }, { timeout_ms = 2000 }, function(result, cx2)
		local live = cx2 or cx
		local path = if result.status == 0 then normalize(result.stdout or "") else ""
		if local_image(path) then
			done(live, path)
			return
		end
		tern.process.run({ "pbpaste" }, { timeout_ms = 1000 }, function(text, cx3)
			local live3 = cx3 or live
			local pasted = if text.status == 0 then normalize(text.stdout or "") else ""
			done(live3, if local_image(pasted) then pasted else "")
		end)
	end)
end

local function send_image(cx: any)
	if cx == nil then
		return
	end
	if not macos() then
		toast(cx, "info", "Image upload requires macOS", "Use ordinary paste for other clipboard content")
		return
	end
	local host, pane_id = destination(cx)
	if host == nil or pane_id == nil then
		toast(cx, "info", "Select a remote pane to upload an image", "Ordinary paste is unchanged")
		return
	end
	log("send-image")
	read_image(cx, function(live, path)
		log("send-image path=" .. path .. " host=" .. tostring(host.name))
		if path ~= "" then
			deliver(live, host, path, pane_id)
		else
			toast(live, "info", "Copy an image file or its absolute path first", "Use Cmd+V for ordinary paste")
		end
	end)
end

local command: { [string]: any } = {
	id = "send-image",
	title = "Send clipboard image to the current remote",
	icon = "image",
	run = send_image,
}
if macos() then
	command.keys = { "cmd+alt+shift+i" }
end
tern.command(command)
