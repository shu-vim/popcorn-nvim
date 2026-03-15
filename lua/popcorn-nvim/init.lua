local M = {}

M.config = {
  menu = {
    {
      name = 'LSP',
      sub = {
        {
          name = 'CodeAction',
          action = 'lua vim.lsp.buf.code_action()',
          instant = true,
          left = function() vim.diagnostic.jump({ count = -1 }) end,
          right = function() vim.diagnostic.jump({ count = 1 }) end,
        },
        {
          name = 'Diagnostic',
          action = 'lua vim.diagnostic.open_float({ border = "single" })',
          left = function() vim.diagnostic.jump({ count = -1 }) end,
          right = function() vim.diagnostic.jump({ count = 1 }) end,
        },
        { name = 'Definition', action = 'lua vim.lsp.buf.definition()' },
        { name = 'Hover', action = 'lua vim.lsp.buf.hover()', default = true },
        { name = 'Rename', action = 'lua vim.lsp.buf.rename()' },
      },
    },
    {
      name = 'Color',
      sub = {
        { name = 'default', action = 'colorschem default', instant = true },
        { name = '-' },
        {
          name = 'Toggle',
          nameeval = 'printf("Toggle %s", (&background == "dark" ? "light" : "dark"))',
          action = function()
            local colors_name = vim.g.colors_name
            if vim.o.background == 'dark' then
              vim.o.background = 'light'
            else
              vim.o.background = 'dark'
            end
            vim.cmd('colorscheme ' .. colors_name)
            vim.cmd('silent syn on')
          end,
          default = true,
        },
        { name = '-' },
        { name = 'SynOn', action = 'syn on' },
      },
    },
    {
      name = 'Tab',
      sub = {
        { name = 'Only', action = 'tabonly', default = true },
      },
    },
    {
      name = 'Window',
      sub = {
        {
          name = 'Alt',
          action = function() pcall(vim.cmd, 'buffer ' .. vim.fn.bufnr('#')) end,
          default = true,
        },
        { name = 'Split(--)', action = 'split' },
        { name = 'Split(|)', action = 'vsplit' },
      },
    },
    { name = '-' },
    { name = 'Buffer', nameeval = '&fileformat .. " / " .. &fileencoding', skip = true },
    { name = 'Time', nameeval = 'strftime("%Y-%m-%d %H:%M:%S")', skip = true },
    { name = '? : help', skip = true },
  },
  HLGroup = 'Comment',
  HLSeparator = 'Comment',
  HLSkip = 'Comment',

  EscToBack = false,
}

---@usage `require('popcorn-nvim').setup({ ...configs... })`
M.setup = function(args) M.config = vim.tbl_deep_extend('force', M.config, args or {}) end

M.execute = function()
  local menu_close
  local help_toggle
  local menu_move_selection
  local menu_climb_down
  local menu_climb_up
  local menu_execute_item
  --
  local menu_border
  local redraw
  local build_item_lines
  local default_indices
  local as_root_item
  local derive_parent
  local name_resolved
  local execute_action_resolved
  local dump

  --------------------

  local main = function()
    local origwin = vim.api.nvim_get_current_win()

    -- cancel if any floating window exists
    for _, win in pairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).zindex then
        local ok, _ = pcall(vim.api.nvim_win_get_var, win, 'breadcrumbs')
        if ok then return end
      end
    end

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'cursor',
      row = 1,
      col = 0,
      width = 1,
      height = 1,
      border = menu_border(),
      noautocmd = true,
    })
    vim.api.nvim_create_autocmd('InsertEnter', {
      buffer = buf,
      callback = function()
        --vim.notify('InsertEnter')
        vim.cmd([[execute "normal \<esc>"]])
      end,
    })
    vim.api.nvim_create_autocmd('BufLeave', {
      buffer = buf,
      callback = function()
        if not vim.api.nvim_win_get_var(win, 'stay') then menu_close(win) end
      end,
    })
    vim.fn.matchadd(M.config.HLGroup, [[\v ([(].*[)])?\s*[>]{2}]], 0, -1, { window = win })
    vim.fn.matchadd(M.config.HLGroup, [[\v ([(].*[)])?$]], 1, -1, { window = win })
    vim.fn.matchadd(M.config.HLSeparator, [[\v-{3,}]], 0, -1, { window = win })
    vim.fn.matchadd(M.config.HLSkip, [[\v^ .*]], 0, -1, { window = win })
    vim.api.nvim_win_set_option(win, 'number', false)
    vim.api.nvim_win_set_option(win, 'relativenumber', false)
    vim.api.nvim_win_set_option(win, 'wrap', false)
    vim.api.nvim_win_set_option(win, 'cursorline', false)
    --vim.api.nvim_win_set_option(win, 'modifiable', false)
    vim.api.nvim_win_set_var(win, 'breadcrumbs', {})
    vim.api.nvim_win_set_var(win, 'stay', false)
    vim.api.nvim_win_set_var(win, 'help_win', -1)

    -- keymap
    if M.config.EscToBack then
      vim.keymap.set('n', '<Esc>', function() menu_climb_up(origwin, win) end, { buffer = buf })
    else
      vim.keymap.set('n', '<Esc>', function() menu_close(win) end, { buffer = buf })
    end
    vim.keymap.set('n', 'q', function() menu_close(win) end, { buffer = buf })
    vim.keymap.set('n', '<Down>', function() menu_move_selection(win, 'down') end, { buffer = buf })
    vim.keymap.set('n', 'j', function() menu_move_selection(win, 'down') end, { buffer = buf })
    vim.keymap.set('n', '<Up>', function() menu_move_selection(win, 'up') end, { buffer = buf })
    vim.keymap.set('n', 'k', function() menu_move_selection(win, 'up') end, { buffer = buf })
    vim.keymap.set('n', '<Right>', function() menu_climb_down(origwin, win, false) end, { buffer = buf })
    vim.keymap.set('n', 'l', function() menu_climb_down(origwin, win, true) end, { buffer = buf })
    vim.keymap.set('n', '<Tab>', function() menu_climb_down(origwin, win, false) end, { buffer = buf })
    vim.keymap.set('n', '<Left>', function() menu_climb_up(origwin, win) end, { buffer = buf })
    vim.keymap.set('n', 'h', function() menu_climb_up(origwin, win, true) end, { buffer = buf })
    vim.keymap.set('n', '<S-Tab>', function() menu_climb_up(origwin, win) end, { buffer = buf })
    vim.keymap.set('n', '<BackSpace>', function() menu_climb_up(origwin, win) end, { buffer = buf })
    vim.keymap.set('n', '<CR>', function() menu_execute_item(origwin, win) end, { buffer = buf })
    vim.keymap.set('n', '<Space>', function() menu_execute_item(origwin, win) end, { buffer = buf })
    vim.keymap.set('n', 'i', function() menu_execute_item(origwin, win, true) end, { buffer = buf })
    vim.keymap.set('n', '?', function() help_toggle(win) end, { buffer = buf })

    redraw(origwin, win, as_root_item(M.config.menu))
  end

  help_toggle = function(win)
    local helpwin = vim.api.nvim_win_get_var(win, 'help_win')
    if helpwin ~= -1 then
      vim.api.nvim_win_set_var(win, 'help_win', -1)
      pcall(vim.api.nvim_win_close, helpwin, false)
      return
    end

    local config = vim.api.nvim_win_get_config(win)

    local buf = vim.api.nvim_create_buf(false, true)
    helpwin = vim.api.nvim_open_win(buf, false, {
      relative = 'win',
      win = win,
      focusable = false,
      row = -1,
      col = config.width + 2,
      width = 1,
      height = 1,
      border = menu_border(),
      title = 'help',
      noautocmd = true,
    })
    vim.api.nvim_win_set_option(helpwin, 'number', false)
    vim.api.nvim_win_set_option(helpwin, 'relativenumber', false)
    vim.api.nvim_win_set_option(helpwin, 'wrap', false)
    vim.api.nvim_win_set_option(helpwin, 'cursorline', false)
    --vim.api.nvim_win_set_option(helpwin, 'modifiable', false)

    vim.api.nvim_win_set_var(win, 'help_win', helpwin)

    local lines = {
      'q/Esc        : close',
      'CR/Space     : select, execute',
      'i            : execute instantly (without closing a floating window)',
      'j/Down       : move cursor',
      'k/Up',
      'h/l          : navigate submenu or execute left/right actions',
      'Left/Right   : navigate submenu',
      'Tab/S-Tab/BackSpace',
    }
    local maxwid = 0
    for i = 1, #lines do
      maxwid = math.max(maxwid, vim.fn.strdisplaywidth(lines[i]))
    end
    vim.api.nvim_win_set_width(helpwin, maxwid)
    vim.api.nvim_win_set_height(helpwin, #lines)

    vim.api.nvim_win_set_option(helpwin, 'readonly', false)
    --vim.api.nvim_win_set_option(helpwin, 'modifiable', true)
    vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(helpwin), 0, -1, true, lines)
    --vim.api.nvim_win_set_option(helpwin, 'modifiable', false)
    vim.api.nvim_win_set_option(helpwin, 'readonly', true)
  end

  menu_close = function(win)
    local helpwin = vim.api.nvim_win_get_var(win, 'help_win')
    if helpwin ~= -1 then
      vim.api.nvim_win_set_var(win, 'help_win', -1)
      pcall(vim.api.nvim_win_close, helpwin, false)
    end

    vim.api.nvim_win_close(win, false)
  end

  menu_move_selection = function(win, direction)
    local root = as_root_item(M.config.menu)
    local breadcrumbs = vim.api.nvim_win_get_var(win, 'breadcrumbs')
    local parent = derive_parent(root, breadcrumbs)

    --vim.notify('breadcrumbs=' .. Dump(breadcrumbs) .. ' => ' .. parent.name, 'debug')

    local delta = 1
    if direction == 'up' then delta = -1 end

    local linenr = vim.fn.line('.')
    local lastnr = vim.fn.line('$')

    local nextnr = (linenr + delta + lastnr - 1) % lastnr + 1

    local count = 0
    while parent.sub[nextnr].name == '-' or parent.sub[nextnr].skip and nextnr ~= linenr do
      nextnr = (nextnr + delta + lastnr - 1) % lastnr + 1
      count = count + 1
      if count > 10 then break end
    end
    vim.cmd('normal ' .. tostring(nextnr) .. 'gg')
  end

  menu_climb_down = function(origwin, win, do_exec)
    local root = as_root_item(M.config.menu)
    local breadcrumbs = vim.api.nvim_win_get_var(win, 'breadcrumbs')
    local parent = derive_parent(root, breadcrumbs)

    --vim.notify('breadcrumbs=' .. Dump(breadcrumbs) .. ' => ' .. parent.name, 'debug')

    local linenr = vim.fn.line('.')

    if do_exec and parent.sub[linenr].right then
      vim.api.nvim_win_set_var(win, 'stay', true)

      vim.api.nvim_set_current_win(origwin)
      execute_action_resolved(parent.sub[linenr].right, origwin, function() vim.api.nvim_set_current_win(win) end)

      vim.api.nvim_win_set_var(win, 'stay', false)
      return
    end

    local item = parent.sub[linenr]
    if not item.sub then return end

    table.insert(breadcrumbs, linenr)
    vim.api.nvim_win_set_var(win, 'breadcrumbs', breadcrumbs)

    redraw(origwin, win, item)
  end

  menu_climb_up = function(origwin, win, do_exec)
    local root = as_root_item(M.config.menu)
    local breadcrumbs = vim.api.nvim_win_get_var(win, 'breadcrumbs')

    if do_exec then
      local parent = derive_parent(root, breadcrumbs)
      local linenr = vim.fn.line('.')
      if parent.sub[linenr].left then
        vim.api.nvim_win_set_var(win, 'stay', true)

        vim.api.nvim_set_current_win(origwin)
        execute_action_resolved(parent.sub[linenr].left, origwin, function() vim.api.nvim_set_current_win(win) end)

        vim.api.nvim_win_set_var(win, 'stay', false)
        return
      end
    end

    if #breadcrumbs == 0 then
      if M.config.EscToBack then menu_close(win) end
      return
    end

    table.remove(breadcrumbs, #breadcrumbs)
    vim.api.nvim_win_set_var(win, 'breadcrumbs', breadcrumbs)

    local parent = derive_parent(root, breadcrumbs)

    --vim.notify('breadcrumbs=' .. Dump(breadcrumbs) .. ' => ' .. parent.name, 'debug')

    redraw(origwin, win, parent)
  end

  menu_execute_item = function(origwin, win, instant)
    local root = as_root_item(M.config.menu)
    local breadcrumbs = vim.api.nvim_win_get_var(win, 'breadcrumbs')
    local parent = derive_parent(root, breadcrumbs)

    --vim.notify('breadcrumbs=' .. Dump(breadcrumbs) .. ' => ' .. parent.name, 'debug')

    local linenr = vim.fn.line('.')

    local item = parent.sub[linenr]

    if instant and not item.instant then return end

    if item.sub then
      local defidxs = default_indices(item)
      if #defidxs ~= 0 then
        for di = 1, #defidxs do
          item = item.sub[defidxs[di]]
        end
      else
        menu_climb_down(origwin, win)
        return
      end
    end

    if instant then
      vim.api.nvim_win_set_var(win, 'stay', true)

      vim.api.nvim_set_current_win(origwin)
      execute_action_resolved(item.action, origwin, function() vim.api.nvim_set_current_win(win) end)

      vim.api.nvim_win_set_var(win, 'stay', false)
    else
      -- close a floating window
      vim.api.nvim_set_current_win(origwin)

      execute_action_resolved(item.action, origwin)
    end
  end

  menu_border = function()
    local border
    if vim.o.ambiwidth == 'double' then
      border = { '*', '-', [[\]], '|', '/', '-', [[\]], '|' }
    else
      border = 'rounded'
    end
    return border
  end

  redraw = function(origwin, win, parent)
    local lines, maxwid = build_item_lines(parent, origwin)
    vim.api.nvim_win_set_width(win, maxwid)
    vim.api.nvim_win_set_height(win, #lines)

    vim.api.nvim_win_set_option(win, 'readonly', false)
    --vim.api.nvim_win_set_option(win, 'modifiable', true)
    vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(win), 0, -1, true, lines)
    --vim.api.nvim_win_set_option(win, 'modifiable', false)
    vim.api.nvim_win_set_option(win, 'readonly', true)

    local config = vim.api.nvim_win_get_config(win)
    config.title = parent.name
    vim.api.nvim_win_set_config(win, config)

    vim.cmd('normal 1gg')
  end

  build_item_lines = function(parent, origwin)
    local maxwid = 0
    for i = 1, #parent.sub do
      local item = parent.sub[i]

      local name = name_resolved(item, origwin)

      if item.skip then
        name = ' ' .. name
      else
        local actions = {}

        local defidxs = default_indices(item)
        if #defidxs ~= 0 then
          local defname = ''
          local curr = item
          for di = 1, #defidxs do
            curr = curr.sub[defidxs[di]]
            if defname ~= '' then defname = defname .. '>>' end
            defname = defname .. name_resolved(curr, origwin)
          end
          table.insert(actions, defname)
        end

        if item.left then table.insert(actions, '<-') end
        if item.right then table.insert(actions, '->') end

        if item.instant then table.insert(actions, '<i>') end

        if #actions > 0 then name = name .. ' (' .. table.concat(actions, '/') .. ')' end
      end

      maxwid = math.max(maxwid, vim.fn.strdisplaywidth(name))

      --vim.notify(item.name .. ' -> ' .. name, 'debug')
      item.name_ = name
    end

    -- centering skip item
    for i = 1, #parent.sub do
      local item = parent.sub[i]
      if item.skip then
        --vim.notify(
        --    'center if skip: maxwid=' ..
        --    tostring(maxwid) .. ', namewid=' .. tostring(vim.fn.strdisplaywidth(item.name_)),
        --    'debug')
        -- item.name_ = vim.fn.repeat(' ', (maxwid - vim.fn.strdisplaywidth(item.name_) / 2) .. item.name_
        item.name_ = string.rep(' ', (maxwid - vim.fn.strdisplaywidth(item.name_)) / 2) .. item.name_
      end
    end

    -- render as {string, ...}
    local lines = {}
    for i = 1, #parent.sub do
      local item = parent.sub[i]
      if item.name == '-' then -- a separator
        table.insert(lines, string.rep('-', maxwid))
      elseif item.sub then
        table.insert(lines, item.name_ .. string.rep(' ', maxwid - vim.fn.strdisplaywidth(item.name_)) .. ' >>')
      else
        table.insert(lines, item.name_)
      end
    end

    return lines, maxwid + 3 -- ' >>'
  end

  default_indices = function(item) -- {number, ...}
    if not item.sub then return {} end

    local result = {}
    local curr = item
    local idx = 1
    while true do
      if not curr.sub then break end
      if #curr.sub < idx then break end

      --vim.notify('idx = ' .. tostring(idx), 'debug')
      local child = curr.sub[idx]
      if child.default then
        table.insert(result, idx)
        curr = child
        idx = 1
        --vim.notify('curr is ' .. curr.name, 'debug')
      else
        idx = idx + 1
      end
    end

    return result
  end

  as_root_item = function(item)
    if item.sub then return item end
    return { name = '', sub = vim.deepcopy(item) }
  end

  derive_parent = function(root, breadcrumbs)
    local parent = root
    for i = 1, #breadcrumbs do
      parent = parent.sub[breadcrumbs[i]]
    end
    return parent
  end

  name_resolved = function(item, origwin)
    local name
    if item.nameeval then
      name = vim.api.nvim_win_call(origwin, function() return vim.api.nvim_eval(item.nameeval) end)
    else
      name = item.name
    end
    return vim.trim(name)
  end

  execute_action_resolved = function(action, origwin, after)
    if not action then return end

    vim.defer_fn(function()
      if action then
        if type(action) == 'string' then
          vim.fn.execute(action)
        elseif type(action) == 'function' then
          action(origwin)
        else
          for i = 1, #action do
            local a = action[i]
            if type(a) == 'string' then
              vim.fn.execute(a)
            elseif type(a) == 'function' then
              a(origwin)
            end
          end
        end
      end

      if after then after() end
    end, 20)
  end

  -- luacheck: no unused
  ---@diagnostic disable-next-line: unused-function
  dump = function(v, indent)
    if type(v) == 'nil' then
      return 'nil'
    elseif type(v) == 'string' then
      return '"' .. v .. '"'
    elseif type(v) == 'number' then
      return tostring(v)
    elseif type(v) == 'boolean' then
      return tostring(v)
    elseif type(v) == 'table' then
      if #v < 5 then
        local s = '{'
        for k, vv in pairs(v) do
          if type(k) == 'number' then
            s = s .. '[' .. tostring(k) .. ']'
          else
            s = s .. k
          end
          s = s .. ' = ' .. dump(vv) .. ', '
        end
        s = s .. '}'
        return s
      else
        local s = '{\n'
        indent = (indent or 0) + 1
        for k, vv in pairs(v) do
          s = s .. string.rep('  ', indent)
          if type(k) == 'number' then
            s = s .. '[' .. tostring(k) .. ']'
          else
            s = s .. k
          end
          s = s .. ' = ' .. dump(vv, indent) .. ',\n'
        end
        s = s .. '}\n'
        return s
      end
    end
  end

  --------------------

  main()
end

--- adds a top-level menu item.
--- @param item table : item to be added
--- @param name_elder string :  (optional) `item` is added after an item named `name_elder`
--- @usage `:lua require('popcorn-nvim').add({name='MyItem', action='lua print("aaa")'})`
M.add = function(item, name_elder)
  if type(item) ~= 'table' then
    vim.notify('Popcorn: item should be a table')
    return
  end

  if not item.name then
    vim.notify('Popcor: name required')
    return
  end

  if not item.action and not item.left and not item.right and not item.sub and (item.name and item.name ~= '-') then
    vim.notify('Popcor: action, left, right, sub or name(that is ' - ') required')
    return
  end

  if not name_elder then
    table.insert(M.config.menu, item)
    return
  end

  local idx
  for i = 1, #M.config.menu do
    if M.config.menu[i].name == name_elder then idx = i end
  end
  if not idx then
    table.insert(M.config.menu, item)
    return
  end
  table.insert(M.config.menu, idx + 1, item)
end

--- Removes a top-level menu item.
--- @param name string : being removed name of an item
M.remove = function(name)
  local idx
  for i = 1, #M.config.menu do
    if M.config.menu[i].name == name then idx = i end
  end
  if not idx then return end
  table.remove(M.config.menu, idx)
end

--- replaces a top-level menu item.
--- @param item table : item to be added
--- @param name string : (optional) `item` is added in change of an item named `name`
M.replace = function(item, name)
  if type(item) ~= 'table' then
    vim.notify('Popcorn: item should be a table')
    return
  end

  if not item.name then
    vim.notify('Popcor: name required')
    return
  end

  if not item.action and not item.left and not item.right and not item.sub and (item.name and item.name ~= '-') then
    vim.notify('Popcor: action, left, right, sub or name(that is ' - ') required')
    return
  end

  if not name then
    table.insert(M.config.menu, item)
    return
  end

  local idx
  for i = 1, #M.config.menu do
    if M.config.menu[i].name == name then idx = i end
  end
  if not idx then
    table.insert(M.config.menu, item)
    return
  end
  table.insert(M.config.menu, idx + 1, item)
  table.remove(M.config.menu, idx)
end

return M

-- vim: set et ft=lua sts=2 sw=2 ts=2 :
