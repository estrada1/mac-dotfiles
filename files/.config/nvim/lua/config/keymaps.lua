-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

-- Split a single-line shell command into multi-line flag-per-line format.
-- Each " --flag" becomes " \<newline>--flag". Works on the current line.
vim.keymap.set("n", "<leader>cs", function()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  local indent = line:match("^(%s*)")
  local result = line:gsub(" (%-%-)", " \\\n" .. indent .. "%1")
  local new_lines = vim.split(result, "\n")
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, new_lines)
end, { desc = "Split shell flags to multi-line" })

-- Paste a URL from the clipboard as a markdown link, fetching the page title.
-- Inspired by org-cliplink for Emacs. Async via vim.system().
vim.keymap.set("n", "<leader>ml", function()
  local url = vim.trim(vim.fn.getreg("+"))
  if not url:match("^https?://") then
    vim.notify("Clipboard does not contain an HTTP(S) URL", vim.log.levels.WARN)
    return
  end

  -- Remember cursor position and buffer so the async callback can insert there.
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)

  vim.system(
    { "curl", "-sL", "--compressed", "--max-time", "10",
      "-H", "User-Agent: Mozilla/5.0", url },
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 or not result.stdout then
        vim.notify("Failed to fetch URL", vim.log.levels.ERROR)
        return
      end

      -- Extract <title> (case-insensitive, may span multiple lines).
      local title = result.stdout:match("<[Tt][Ii][Tt][Ll][Ee][^>]*>(.-)<%s*/[Tt][Ii][Tt][Ll][Ee]>")
      if title then
        -- Collapse whitespace (titles often span lines).
        title = title:gsub("%s+", " ")
        title = vim.trim(title)
        -- Decode numeric HTML entities (&#NNN; and &#xHH;).
        title = title:gsub("&#x(%x+);", function(h) return vim.fn.nr2char(tonumber(h, 16)) end)
        title = title:gsub("&#(%d+);", function(d) return vim.fn.nr2char(tonumber(d)) end)
        -- Decode common named HTML entities.
        local entities = {
          ["&amp;"] = "&", ["&lt;"] = "<", ["&gt;"] = ">",
          ["&quot;"] = '"', ["&apos;"] = "'", ["&nbsp;"] = " ",
          ["&ndash;"] = "–", ["&mdash;"] = "—",
          ["&laquo;"] = "«", ["&raquo;"] = "»",
          ["&copy;"] = "©", ["&reg;"] = "®",
          ["&trade;"] = "™",
        }
        for ent, char in pairs(entities) do
          title = title:gsub(ent, char)
        end
        -- Straighten curly quotes (like org-cliplink does).
        title = title:gsub("\u{2018}", "'"):gsub("\u{2019}", "'")
        title = title:gsub("\u{201C}", '"'):gsub("\u{201D}", '"')
        -- Escape markdown brackets in the title.
        title = title:gsub("%[", "\\["):gsub("%]", "\\]")
      end

      local link
      if title and #title > 0 then
        link = string.format("[%s](%s)", title, url)
      else
        link = string.format("[](%s)", url)
      end

      -- Insert at the saved cursor position.
      if vim.api.nvim_buf_is_valid(buf) then
        local row, col = cursor[1], cursor[2]
        vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { link })
      end
    end)
  )
end, { desc = "Paste clipboard URL as markdown link" })

-- Toggle markdown checkbox: insert one on empty lines, cycle [ ] -> [/] -> [x] -> [ ] otherwise.
local function toggle_checkbox()
  local line = vim.api.nvim_get_current_line()
  if line:match("^%s*$") then
    local indent = line:match("^(%s*)")
    vim.api.nvim_set_current_line(indent .. "- [ ] ")
    vim.cmd("startinsert!")
  elseif line:match("%[x%]") then
    vim.api.nvim_set_current_line((line:gsub("%[x%]", "[ ]", 1)))
  elseif line:match("%[/%]") then
    vim.api.nvim_set_current_line((line:gsub("%[/%]", "[x]", 1)))
  elseif line:match("%[ %]") then
    vim.api.nvim_set_current_line((line:gsub("%[ %]", "[/]", 1)))
  else
    local indent, rest = line:match("^(%s*)(.*)")
    vim.api.nvim_set_current_line(indent .. "- [ ] " .. rest)
  end
end

-- Visual mode: convert bullets to checkboxes, or toggle checkbox state on selected lines.
local function toggle_checkbox_visual()
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then start_line, end_line = end_line, start_line end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  -- Decide action: if any line is a plain bullet (no checkbox), convert all bullets to checkboxes.
  -- Otherwise, determine majority state and flip all checkboxes.
  local has_plain_bullet = false
  local checked, unchecked, in_progress = 0, 0, 0
  for _, l in ipairs(lines) do
    if l:match("^%s*[-*+] %[x%]") then
      checked = checked + 1
    elseif l:match("^%s*[-*+] %[/%]") then
      in_progress = in_progress + 1
    elseif l:match("^%s*[-*+] %[ %]") then
      unchecked = unchecked + 1
    elseif l:match("^%s*[-*+] ") then
      has_plain_bullet = true
    end
  end

  for i, l in ipairs(lines) do
    if has_plain_bullet then
      -- Convert plain bullets to unchecked checkboxes (leave existing checkboxes alone).
      if l:match("^%s*[-*+] ") and not l:match("%[.%]") then
        lines[i] = l:gsub("^(%s*[-*+]) ", "%1 [ ] ", 1)
      end
    elseif unchecked >= checked and unchecked >= in_progress then
      -- Majority unchecked → mark in-progress
      lines[i] = l:gsub("%[ %]", "[/]", 1)
    elseif in_progress >= checked then
      -- Majority in-progress → check all
      lines[i] = l:gsub("%[/%]", "[x]", 1)
    else
      -- Majority checked → uncheck all
      lines[i] = l:gsub("%[x%]", "[ ]", 1)
    end
  end

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

vim.keymap.set("n", "<leader>mt", toggle_checkbox, { desc = "Toggle markdown checkbox" })
vim.keymap.set("v", "<leader>mt", toggle_checkbox_visual, { desc = "Toggle markdown checkboxes (visual)" })

-- In todo/**/*.md files, <Tab> also toggles checkboxes for quick entry.
local function setup_todo_tab(buf)
  vim.keymap.set("n", "<Tab>", toggle_checkbox, { buffer = buf, desc = "Toggle markdown checkbox" })
  vim.keymap.set("v", "<Tab>", toggle_checkbox_visual, { buffer = buf, desc = "Toggle markdown checkboxes (visual)" })
end

vim.api.nvim_create_autocmd("BufEnter", {
  pattern = { "**/todo/*.md", "**/todo/**/*.md" },
  callback = function(ev) setup_todo_tab(ev.buf) end,
})

-- Apply now if the current buffer is already under a todo/ dir (VeryLazy loads after BufReadPost).
if vim.fn.expand("%:p"):match("/todo/.*%.md$") then
  setup_todo_tab(0)
end

-- Indent left/right with Alt+h / Alt+l (overrides LazyVim window-nav defaults).
vim.keymap.set("n", "<A-h>", "<<", { desc = "Indent left" })
vim.keymap.set("n", "<A-l>", ">>", { desc = "Indent right" })
vim.keymap.set("v", "<A-h>", "<gv", { desc = "Indent left" })
vim.keymap.set("v", "<A-l>", ">gv", { desc = "Indent right" })

-- Copy the current file's absolute path to the system clipboard.
vim.keymap.set("n", "<leader>cp", function()
  local path = vim.fn.expand("%:p")
  vim.fn.setreg("+", path)
  vim.notify("Copied: " .. path)
end, { desc = "Copy file path" })
