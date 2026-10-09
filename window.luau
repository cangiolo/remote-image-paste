--!strict
-- macOS clipboard image -> SSH upload -> paste the server path into the
-- focused remote pane. The Tern display name must already be an ssh target.

local EXT: { [string]: boolean } = { png = true, jpg = true, jpeg = true, gif = true, webp = true }
local FILE_URL = [[try
POSIX path of (the clipboard as «class furl»)
on error
""
end try]]
local DISCOVER = 't=$(command -v tern 2>/dev/null || true); if [ -z "$t" ] && [ -x "$HOME/.local/share/tern/build/tern" ]; then t="$HOME/.local/share/tern/build/tern"; fi; printf %s "$t"'

local busy = false
local replaying = false

local function log(message: string)
	tern.log.info(message)
end

local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

local function shquote(text: string): string
	return "'" .. string.gsub(text, "'", "'\\''") .. "'"
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

local function remote_host(host: any): boolean
	return type(host) == "table"
		and host.kind == "remote"
		and (host.state == "connected" or host.state == "stalled")
end

local function destination(cx: any): (any?, number?, string)
	local pane_id = focused_id(cx)
	local host = if pane_id ~= nil then host_owning(cx, pane_id) else nil
	if not remote_host(host) then
		local ok, current = pcall(function()
			return cx.hosts:current()
		end)
		if ok and remote_host(current) then
			host = current
		else
			return nil, pane_id, ""
		end
	end
	local block = "@focused"
	if pane_id ~= nil then
		local ok, pane = pcall(function()
			return cx.session:pane(pane_id)
		end)
		if ok and type(pane) == "table" and type(pane.title) == "string" and pane.title ~= "" then
			block = pane.title
		end
	end
	return host, pane_id, block
end

local function insert_path(cx: any, pane_id: number?, text: string): boolean
	if cx == nil or pane_id == nil then
		return false
	end
	local ok, err = pcall(function()
		cx:run(pane_id, text)
	end)
	if not ok then
		log("insert failed " .. tostring(err))
	end
	return ok
end

local function safe_bin(text: string): string?
	if text == "" or string.find(text, "\n", 1, true) ~= nil or string.sub(text, 1, 1) == "-" then
		return nil
	end
	return text
end

local function paste_server_path(cx: any, target: string, pane_id: number?, abs: string, block: string)
	tern.process.run({ "ssh", "-o", "BatchMode=yes", target, DISCOVER }, { timeout_ms = 15000 }, function(found, cx2)
		local live = cx2 or cx
		local bin = safe_bin(trim(found.stdout or ""))
		if found.status ~= 0 or bin == nil then
			busy = false
			if insert_path(live, pane_id, abs) then
				toast(live, "success", "Path inserted", abs)
			else
				toast(live, "error", "Paste failed", abs)
			end
			return
		end
		local cmd = shquote(bin) .. " send " .. shquote(block) .. " paste " .. shquote(abs)
		log("inject " .. block .. " <- " .. abs)
		tern.process.run({ "ssh", "-o", "BatchMode=yes", target, cmd }, { timeout_ms = 15000 }, function(sent, cx3)
			local live3 = cx3 or live
			busy = false
			if sent.status ~= 0 then
				log("remote paste failed " .. trim(sent.stderr or ""))
				if insert_path(live3, pane_id, abs) then
					toast(live3, "success", "Path inserted", abs)
				else
					toast(live3, "error", "Paste failed", trim(sent.stderr or ""))
				end
				return
			end
			log("injected " .. abs)
			toast(live3, "success", "Pasted", abs)
		end)
	end)
end

local function deliver(cx: any, host: any, local_path: string, pane_id: number?, block: string)
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
			paste_server_path(live3, target, pane_id, abs, block)
		end)
	end)
end

local function replay_paste(cx: any, command_id: string?)
	if cx == nil then
		return
	end
	replaying = true
	local ok, err = pcall(function()
		cx:action(command_id or "canvas.paste")
	end)
	replaying = false
	if not ok then
		log("replay " .. tostring(command_id) .. " failed " .. tostring(err))
	end
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

local function on_paste(cx: any, command_id: string?): boolean
	if replaying or cx == nil or not macos() then
		return false
	end
	local host, pane_id, block = destination(cx)
	if host == nil then
		return false
	end
	if busy then
		toast(cx, "info", "Busy")
		return true
	end
	local replay_as = command_id or "canvas.paste"
	read_image(cx, function(live, path)
		if path ~= "" then
			deliver(live, host, path, pane_id, block)
		else
			replay_paste(live, replay_as)
		end
	end)
	return true
end

local function send_image(cx: any)
	if replaying or cx == nil then
		return
	end
	if not macos() then
		toast(cx, "error", "macOS only")
		return
	end
	if not on_paste(cx, "canvas.paste") then
		toast(cx, "error", "No host")
	end
end

for _, command_id in { "paste", "canvas.paste" } do
	local override_ok, override_err = pcall(function()
		tern.override(command_id, function(cx)
			if on_paste(cx, command_id) then
				return true
			end
			return nil
		end)
	end)
	if not override_ok then
		log("override " .. command_id .. " failed " .. tostring(override_err))
	end
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
