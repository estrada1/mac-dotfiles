--- Build an scp command for the selected (or hovered) files and copy it to the clipboard.
--- Uses $SSH_CONNECTION to determine the server IP the client connected via.

-- Sync block: extracts file paths from cx (only available in sync context)
local collect_paths = ya.sync(function()
	local paths = {}
	local selected = cx.active.selected
	if #selected > 0 then
		for _, url in pairs(selected) do
			paths[#paths + 1] = tostring(url)
		end
	else
		local hovered = cx.active.current.hovered
		if hovered then
			paths[#paths + 1] = tostring(hovered.url)
		end
	end
	return paths
end)

return {
	entry = function()
		local paths = collect_paths()
		if #paths == 0 then return end

		local ssh = os.getenv("SSH_CONNECTION") or ""
		local ip = ssh:match("^%S+%s+%S+%s+(%S+)")
		if not ip then
			ya.notify { title = "scp-clip", content = "Not in an SSH session", timeout = 3 }
			return
		end

		local user = os.getenv("USER") or "unknown"
		local parts = { "scp -r" }
		for _, p in ipairs(paths) do
			parts[#parts + 1] = user .. "@" .. ip .. ":" .. p
		end
		parts[#parts + 1] = "."
		local cmd = table.concat(parts, " ")

		ya.clipboard(cmd)
		ya.notify { title = "scp-clip", content = "Copied: " .. cmd, timeout = 3 }
	end,
}
