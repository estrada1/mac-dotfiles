--- Zip selected (or hovered) files/dirs.
--- Single selection: uses the item's name as the archive name.
--- Multiple selections: prompts the user for a name.

local get_paths = ya.sync(function()
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

local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local function basename(path)
	return path:match("([^/]+)/?$") or path
end

local function strip_ext(name)
	return name:match("^(.+)%..+$") or name
end

return {
	entry = function()
		local paths = get_paths()
		if #paths == 0 then return end
		local cwd = get_cwd()

		local name
		if #paths == 1 then
			name = strip_ext(basename(paths[1]))
		else
			local input, event = ya.input {
				title = "Zip archive name (without .zip):",
				pos = { "center", w = 50 },
			}
			if event ~= 1 or not input or input == "" then return end
			name = input
		end

		local archive = name .. ".zip"

		local args = { "-r", archive }
		for _, p in ipairs(paths) do
			args[#args + 1] = basename(p)
		end

		local status, err = Command("zip"):arg(args):cwd(cwd):status()
		if not status then
			ya.notify { title = "zip", content = "Failed to run zip: " .. tostring(err), level = "error", timeout = 5 }
			return
		end

		if status.success then
			ya.notify { title = "zip", content = "Created " .. archive, timeout = 3 }
		else
			ya.notify { title = "zip", content = "zip failed (exit " .. tostring(status.code) .. ")", level = "error", timeout = 5 }
		end
	end,
}
