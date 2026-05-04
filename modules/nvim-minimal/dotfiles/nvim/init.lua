-- Minimal, plugin-free Neovim config.
-- Used on hosts (e.g. auth VPS) where the full LazyVim setup isn't desired,
-- and as a self-contained drop-in for unmanaged remote boxes.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
local o = vim.opt
o.number = true
o.relativenumber = true
o.mouse = "a"
o.cursorline = true
o.signcolumn = "yes"
o.scrolloff = 8
o.sidescrolloff = 8
o.wrap = false
o.linebreak = true

o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.softtabstop = 2
o.smartindent = true

o.ignorecase = true
o.smartcase = true
o.incsearch = true
o.hlsearch = true

o.splitright = true
o.splitbelow = true
o.termguicolors = true
o.showmode = false
o.updatetime = 250
o.timeoutlen = 400
o.confirm = true
o.undofile = true

o.list = true
o.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- ---------------------------------------------------------------------------
-- Clipboard: OSC 52 over SSH (works in any modern terminal, no xclip needed)
-- ---------------------------------------------------------------------------
local ok_osc, osc52 = pcall(require, "vim.ui.clipboard.osc52")
if ok_osc then
  vim.g.clipboard = {
    name = "OSC52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
  }
end
o.clipboard = "unnamedplus"

-- ---------------------------------------------------------------------------
-- Keymaps (mirroring the most-used bindings from the full config)
-- ---------------------------------------------------------------------------
local map = vim.keymap.set

-- Centered movement
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")
map("n", "G", "Gzz")
map("n", "gg", "ggzz")
map("n", "J", "mzJ`z")

-- Insert blank line without leaving normal mode
map("n", "zj", "o<Esc>k", { desc = "Blank line below" })
map("n", "zk", "O<Esc>j", { desc = "Blank line above" })

-- Visual block under <C-b> (some terminals eat <C-v>)
map("n", "<C-b>", "<C-v>")
map("i", "<C-c>", "<Esc>")

-- Move lines
map("n", "<S-Up>", "ddkP", { desc = "Move line up" })
map("n", "<S-Down>", "ddp", { desc = "Move line down" })
map("n", "<C-j>", "<cmd>m .+1<cr>==", { desc = "Move down" })
map("n", "<C-k>", "<cmd>m .-2<cr>==", { desc = "Move up" })
map("v", "<C-j>", ":m '>+1<cr>gv=gv", { desc = "Move down" })
map("v", "<C-k>", ":m '<-2<cr>gv=gv", { desc = "Move up" })

-- Selection helpers
map("n", "L", "vg_", { desc = "Select to end of line" })
map("n", "<C-a>", "ggVG", { desc = "Select all" })
map("n", "gp", "`[v`]", { desc = "Reselect last paste/yank/change" })

-- Clipboard (OSC 52 via "+")
map({ "n", "v" }, "<leader>y", '"+y', { desc = "Yank to clipboard" })
map("n", "<leader>Y", function()
  vim.cmd("normal! ggVG")
  vim.cmd('normal! "+y')
end, { desc = "Copy whole file to clipboard" })
map({ "n", "v" }, "<leader>p", '"+p', { desc = "Paste from clipboard" })
map({ "n", "v" }, "<leader>d", '"_d', { desc = "Delete without yank" })
map(
  "n",
  "<leader>fN",
  ':let @+ = expand("%:p")<cr>:lua print("Copied: " .. vim.fn.expand("%:p"))<cr>',
  { desc = "Copy current file path", silent = false }
)

-- Search & misc
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>W", "<cmd>w !sudo tee % > /dev/null<cr>", { desc = "Save with sudo" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
map("n", "<leader>Q", "<cmd>qa!<cr>", { desc = "Quit all (force)" })

-- Buffers
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete buffer" })

-- Windows
map("n", "<C-h>", "<C-w>h")
map("n", "<C-Left>", "<C-w>h")
map("n", "<C-Right>", "<C-w>l")
map("n", "<C-Up>", "<C-w>k")
map("n", "<C-Down>", "<C-w>j")
map("n", "<leader>-", "<cmd>split<cr>", { desc = "Split below" })
map("n", "<leader>|", "<cmd>vsplit<cr>", { desc = "Split right" })

-- Better indenting in visual
map("v", "<", "<gv")
map("v", ">", ">gv")

-- File explorer (built-in netrw)
map("n", "<leader>e", "<cmd>Explore<cr>", { desc = "File explorer (netrw)" })

-- Search & replace word under cursor in current file
map(
  "n",
  "<leader>S",
  ":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gIc<Left><Left><Left><Left>",
  { desc = "Replace word under cursor" }
)

-- Quick comment toggle (line) — language-agnostic via Neovim 0.10+ built-in
map("n", "<C-z>", "gcc", { remap = true, desc = "Toggle comment" })
map("v", "<C-z>", "gc", { remap = true, desc = "Toggle comment" })

-- ---------------------------------------------------------------------------
-- Autocommands
-- ---------------------------------------------------------------------------
local aug = vim.api.nvim_create_augroup("nvim_minimal", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = aug,
  callback = function()
    (vim.hl or vim.highlight).on_yank({ timeout = 150 })
  end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  group = aug,
  callback = function(args)
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    local lcount = vim.api.nvim_buf_line_count(args.buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})
