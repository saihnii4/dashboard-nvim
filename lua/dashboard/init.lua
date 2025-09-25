local api, fn = vim.api, vim.fn
local utils = require('dashboard.utils')
local ctx = {}
local db = {}

db.__index = db
db.__newindex = function(t, k, v)
  rawset(t, k, v)
end

local function clean_ctx()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

local function cache_dir()
  local dir = utils.path_join(vim.fn.stdpath('cache'), 'dashboard')
  if fn.isdirectory(dir) == 0 then
    fn.mkdir(dir, 'p')
  end
  return dir
end

local function cache_path()
  local dir = cache_dir()
  return utils.path_join(dir, 'cache')
end

local function default_options()
  return {
    theme = 'hyper',
    disable_move = false,
    shortcut_type = 'letter',
    shuffle_letter = false,
    letter_list = 'abcdefghilmnopqrstuvwxyz',
    buffer_name = 'Dashboard',
    change_to_vcs_root = false,
    config = {
      extra_components = {},
      week_header = {
        enable = false,
        concat = nil,
        append = nil,
      },
    },
    hide = {
      statusline = true,
      tabline = true,
    },
    preview = {
      command = '',
      file_path = nil,
      file_height = 0,
      file_width = 0,
    },
  }
end

local function buf_local()
  local opts = {
    ['bufhidden'] = 'wipe',
    ['colorcolumn'] = '',
    ['foldcolumn'] = '0',
    ['matchpairs'] = '',
    ['buflisted'] = false,
    ['cursorcolumn'] = false,
    ['cursorline'] = false,
    ['list'] = false,
    ['number'] = false,
    ['relativenumber'] = false,
    ['spell'] = false,
    ['swapfile'] = false,
    ['readonly'] = false,
    ['filetype'] = 'dashboard',
    ['wrap'] = false,
    ['signcolumn'] = 'no',
  }
  for opt, val in pairs(opts) do
    vim.opt_local[opt] = val
  end
  if fn.has('nvim-0.9') == 1 then
    vim.opt_local.stc = ''
  end
end

function db:new_file()
  vim.cmd('enew')
end

function db:save_user_options()
  self.user_cursor_line = vim.opt.cursorline:get()
  self.user_laststatus_value = vim.opt.laststatus:get()
  self.user_tabline_value = vim.opt.showtabline:get()
  self.user_winbar_value = vim.opt.winbar:get()
end

function db:set_ui_options(opts)
  if opts.hide.statusline then
    vim.opt.laststatus = 0
  end
  if opts.hide.tabline then
    vim.opt.showtabline = 0
  end
  if opts.hide.winbar then
    vim.opt.winbar = ''
  end
end

function db:restore_user_options(opts)
  if self.user_cursor_line then
    vim.opt.cursorline = self.user_cursor_line
  end

  if opts.hide.statusline and self.user_laststatus_value then
    vim.opt.laststatus = tonumber(self.user_laststatus_value)
  end

  if opts.hide.tabline and self.user_tabline_value then
    vim.opt.showtabline = tonumber(self.user_tabline_value)
  end

  if opts.hide.winbar and self.user_winbar_value then
    vim.opt.winbar = self.user_winbar_value
  end
end

function db:get_opts(callback)
  vim.schedule_wrap(function(data)
    if not data or #data == 0 then
      return
    end
    local obj = vim.json.decode(data)
    if obj then
      callback(obj)
    end
  end)
end

function db:load_theme(opts)
  local config = vim.tbl_extend('force', opts.config, {
    path = cache_path(),
    bufnr = self.bufnr,
    winid = self.winid,
    confirm_key = opts.confirm_key or nil,
    shortcuts_left_side = opts.shortcuts_left_side,
    shortcut_type = opts.shortcut_type,
    shuffle_letter = opts.shuffle_letter,
    letter_list = opts.letter_list,
    change_to_vcs_root = opts.change_to_vcs_root,
  })

  if #opts.preview.command > 0 then
    config = vim.tbl_extend('force', config, opts.preview)
  end

  require('dashboard.theme.' .. opts.theme)(config)

  self:set_ui_options(opts)

  api.nvim_create_autocmd('VimResized', {
    buffer = self.bufnr,
    callback = function()
      require('dashboard.theme.' .. opts.theme)(config)
      vim.bo[self.bufnr].modifiable = false
    end,
  })

  api.nvim_create_autocmd('BufEnter', {
    callback = function(opt)
      if vim.bo.filetype == 'dashboard' then
        self:set_ui_options(opts)
        return
      end

      local bufs = api.nvim_list_bufs()

      bufs = vim.tbl_filter(function(k)
        return vim.bo[k].filetype == 'dashboard'
      end, bufs)

      -- restore the user's UI settings is no dashboard buffers are visible
      local wins = api.nvim_tabpage_list_wins(0)
      wins = vim.tbl_filter(function(k)
        return vim.tbl_contains(bufs, api.nvim_win_get_buf(k))
      end, wins)

      if #wins == 0 then
        self:restore_user_options(opts)
      end

      -- clean up if there are no dashboard buffers at all
      if #bufs == 0 then
        clean_ctx()
        pcall(api.nvim_del_autocmd, opt.id)
      end
    end,
    desc = '[Dashboard] clean dashboard data reduce memory',
  })
end

-- create dashboard instance
function db:instance()
  local mode = api.nvim_get_mode().mode
  if mode == 'i' or not vim.bo.modifiable then
    return
  end

  if not vim.o.hidden and vim.bo.modified then
    --save before open
    vim.cmd.write()
    return
  end

  if not utils.buf_is_empty(0) then
    self.bufnr = api.nvim_create_buf(false, true)
  else
    self.bufnr = api.nvim_get_current_buf()
  end

  self.winid = api.nvim_get_current_win()
  api.nvim_win_set_buf(self.winid, self.bufnr)

  self:save_user_options()

  buf_local()
  if self.opts then
    self:load_theme(self.opts)
  else
    self:get_opts(function(obj)
      self:load_theme(obj)
    end)
  end
end

function db.setup(opts)
  opts = opts or {}
  ctx.opts = vim.tbl_deep_extend('force', default_options(), opts)
end

return setmetatable(ctx, db)
