local lib = require("neotest.lib")
local logger = require("neotest.logging")

local M = {}

---@async
---Add test instances for path in root to positions
---@param positions neotest.Tree
---@param test_params table<string, string[]>
local function add_test_instances(positions, test_params)
  for _, node in positions:iter_nodes() do
    local position = node:data()
    if position.type == "test" then
      local pos_params = test_params[position.id] or {}
      for _, params_str in ipairs(pos_params) do
        local new_data = vim.tbl_extend("force", position, {
          id = string.format("%s[%s]", position.id, params_str),
          name = string.format("%s[%s]", position.name, params_str),
        })
        new_data.range = nil

        local new_pos = node:new(new_data, {}, node._key, {}, {})
        node:add_child(new_data.id, new_pos)
      end
    end
  end
end

---@async
---@param path string
---@return boolean
local function has_parametrize(path)
  local query = [[
    ;; Detect parametrize decorators
    (decorator
      (call
        function:
          (attribute
            attribute: (identifier) @parametrize
            (#eq? @parametrize "parametrize"))))
  ]]
  local content = lib.files.read(path)
  local ts_root, lang = lib.treesitter.get_parse_root(path, content, { fast = true })
  local built_query = lib.treesitter.normalise_query(lang, query)
  return built_query:iter_matches(ts_root, content)() ~= nil
end

---@async
---Discover test instances for path (by running script using python)
---@param python string[]
---@param script string
---@param path string
---@param positions neotest.Tree
---@param root string
local function discover_params(python, script, path, positions, root)
  local cmd = vim.tbl_flatten({ python, script, "--pytest-collect", path })
  logger.debug("Running test instance discovery:", cmd)

  local test_params = {}
  local res, data = lib.process.run(cmd, { stdout = true, stderr = true })
  if res ~= 0 then
    logger.warn("Pytest discovery failed")
    if data.stderr then
      logger.debug(data.stderr)
    end
    return {}
  end

  for line in vim.gsplit(data.stdout, "\n", true) do
    local match_score = 0
    local test = nil

    for i, pos in positions:iter_nodes() do
      if string.find(line, pos:data().name, nil, true) then
        if (string.find(line, pos:data().name, nil, true) + #pos:data().name) ~= #line and #pos:data().name > match_score then
          match_score = #pos:data().name
          test = pos
        end
      end
    end
    
    if test ~= nil then
      local test_id = test:data().id
      local param_index = string.find(line, test_id, nil, true)
      local param_id = string.sub(line, param_index, #line)
      logger.debug("param_id:", param_id)
      logger.debug("parameterized test:", line)
      logger.debug("associated test, :", test:data().name)
      logger.debug("parameterized test:", line)
      logger.debug("test path:", test:data().path)
      logger.debug("test id:", test:data().id)
      logger.debug("test name:", test:data().name)
      logger.debug("\n")
      if not test_params[test_id] then
        test_params[test_id] = { param_id }
      else
        table.insert(test_params[test_id], param_id)
      end

    end
  end
  return test_params
end

---@async
---Launch pytest to discover test instances for path, if configured
---@param python string[]
---@param script string
---@param path string
---@param positions neotest.Tree
---@param root string
function M.augment_positions(python, script, path, positions, root)
  if has_parametrize(path) then
    logger.debug("has_parametrize:", path)
    local test_params = discover_params(python, script, path, positions, root)
    add_test_instances(positions, test_params)
  end
end

return M
