local utils = require "nvim-tree.utils"
local builders = require "nvim-tree.explorer.node-builders"
local explorer_node = require "nvim-tree.explorer.node"
local sorters = require "nvim-tree.explorer.sorters"
local filters = require "nvim-tree.explorer.filters"
local live_filter = require "nvim-tree.live-filter"
local log = require "nvim-tree.log"

local Watcher = require "nvim-tree.watcher"

local M = {}

local function get_type_from(type_, cwd)
  return type_ or (vim.loop.fs_stat(cwd) or {}).type
end

local function populate_children(handle, cwd, node, git_status)
  local node_ignored = explorer_node.is_git_ignored(node)
  local nodes_by_path = utils.bool_record(node.nodes, "absolute_path")
  local filter_status = filters.prepare(git_status)
  while true do
    local name, t = utils.fs_scandir_next_profiled(handle, cwd)
    if not name then
      break
    end

    local abs = utils.path_join { cwd, name }

    local pn = string.format("explore populate_children %s", abs)
    local ps = log.profile_start(pn)

    t = get_type_from(t, abs)
    if
      not filters.should_filter(abs, filter_status)
      and not nodes_by_path[abs]
      and Watcher.is_fs_event_capable(abs)
    then
      local child = nil
      if t == "directory" and vim.loop.fs_access(abs, "R") then
        child = builders.folder(node, abs, name)
      elseif t == "file" then
        child = builders.file(node, abs, name)
      elseif t == "link" then
        local link = builders.link(node, abs, name)
        if link.link_to ~= nil then
          child = link
        end
      end
      if child then
        table.insert(node.nodes, child)
        nodes_by_path[child.absolute_path] = true
        explorer_node.update_git_status(child, node_ignored, git_status)
      end
    end

    log.profile_end(ps, pn)
  end
end

function M.explore(node, status)
  local cwd = node.link_to or node.absolute_path
  local handle = utils.fs_scandir_profiled(cwd)
  if not handle then
    return
  end

  local pn = string.format("explore init %s", node.absolute_path)
  local ps = log.profile_start(pn)

  populate_children(handle, cwd, node, status)

  local is_root = not node.parent
  local child_folder_only = explorer_node.has_one_child_folder(node) and node.nodes[1]
  if M.config.group_empty and not is_root and child_folder_only then
    node.group_next = child_folder_only
    local ns = M.explore(child_folder_only, status)
    node.nodes = ns or {}

    log.profile_end(ps, pn)
    return ns
  end

  sorters.merge_sort(node.nodes, sorters.node_comparator)
  live_filter.apply_filter(node)

  log.profile_end(ps, pn)
  return node.nodes
end

function M.setup(opts)
  M.config = opts.renderer
end

return M
