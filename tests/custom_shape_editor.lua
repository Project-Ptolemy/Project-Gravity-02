-- Click the actual in-game editor in both panel layouts, then reload its saved file.
-- python tools/test_luau.py --luau PATH_TO_LUAU tests/custom_shape_editor.lua
package.path = "tests/?.lua;" .. package.path
local fixture = require("runtime_fixture")
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function node(name) return assert(fixture.find(name), "Missing editor node: " .. name) end
local function click(name) node(name).Activated:Fire() end
local function text_button(text)
    for _, item in ipairs(fixture.instances) do
        if item._destroyed ~= true and item.Parent and item.ClassName == "TextButton" and item.Text == text then return item end
    end
end
local function slider_value(label)
    for _, item in ipairs(fixture.instances) do
        if item._destroyed ~= true and item.Parent and item.ClassName == "TextLabel" and item.Text == label then
            for _, child in ipairs(item.Parent:GetChildren()) do
                if child.ClassName == "TextBox" then return child.Text end
            end
        end
    end
end

-- Text changes and focus are observable here, so editing an added draft really
-- exercises the editor's change handlers instead of bypassing them.
local factory = Instance.new
Instance.new = function(class, parent)
    local item = factory(class, parent)
    if class == "TextBox" then
        local changed = fixture.signal()
        local meta = getmetatable(item)
        local write, get_signal = meta.__newindex, item.GetPropertyChangedSignal
        meta.__newindex = function(self, key, value)
            local previous = key == "Text" and self.Text
            write(self, key, value)
            if key == "Text" and previous ~= value then changed:Fire() end
        end
        rawset(item, "GetPropertyChangedSignal", function(self, property)
            if property == "Text" then return changed end
            return get_signal(self, property)
        end)
        local focused = false
        rawset(item, "IsFocused", function() return focused end)
        rawset(item, "CaptureFocus", function() focused = true end)
        rawset(item, "ReleaseFocus", function() focused = false end)
        item.Destroying:Connect(function() changed:disconnect() end)
    end
    return item
end

game.HttpGet = function(_, url)
    local path = assert(url:match("/main/(.-)%?cb="), url)
    local file = assert(io.open(path), path)
    local source = file:read("a"); file:close(); return source
end
local source = [[
getgenv()._CUSTOM_IMPORT_RUNS = (getgenv()._CUSTOM_IMPORT_RUNS or 0) + 1
return {
    Controls = { { Type = "Slider", Name = "Import radius", Key = "importRadius", Min = 1, Max = 100, Default = 17 } },
    f2 = function(p, center, d, t, c, x1, x6, x9)
        local target = center + Vector3.new(c.importRadius * math.cos(t), 5, c.importRadius * math.sin(t))
        return (target - p.Position) * (x1.k10 * x9.c1), target
    end,
}
]]
local function memory_disk()
    local files, folders, writes = {}, {}, 0
    isfolder = function(path) return folders[path] == true end
    makefolder = function(path) folders[path] = true end
    isfile = function(path) return files[path] ~= nil end
    listfiles = function(path)
        local list = {}
        for file in pairs(files) do if file:sub(1, #path + 1) == path .. "/" then list[#list + 1] = file end end
        return list
    end
    readfile = function(path) return assert(files[path], "Missing file: " .. path) end
    writefile = function(path, text) files[path] = text; writes = writes + 1 end
    return files, function() return writes end
end

for _, mobile in ipairs({ false, true }) do
    fixture.input.TouchEnabled, fixture.input.KeyboardEnabled = mobile, not mobile
    isfolder, makefolder, isfile, listfiles, readfile, writefile = nil, nil, nil, nil, nil, nil
    getgenv()._CUSTOM_IMPORT_RUNS = 0
    assert(loadfile("main.lua"))()
    local context = assert(getgenv()._GRAVITY_CONTEXT)
    local initial_shape = context.x1.k6
    local mode = mobile and "mobile" or "desktop"
    check(type(context.custom_shapes) == "table", mode .. " initializes custom shape support")
    check(node("CustomShapeEntry").Text == "+ Custom shape", mode .. " exposes the editor in the mode selector")
    click("CustomShapeEntry")
    local editor = node("CustomShapeEditor")
    check(editor.Visible and node("LuaSource").MultiLine and not node("LuaSource").ClearTextOnFocus,
        mode .. " opens a multiline Lua paste field without clearing its contents")
    click("AddShape")
    check(node("ShapeStatus").Text:find("name", 1, true) ~= nil and context.x1.k6 == initial_shape,
        mode .. " reports a missing name without switching the current shape")
    local name = "Imported Orbit " .. mode
    node("ShapeName").Text = name
    node("LuaSource").Text = "return {"
    click("CheckShape")
    check(node("ShapeStatus").Text:find("syntax", 1, true) ~= nil and context.x2[name] == nil,
        mode .. " shows syntax errors inside the editor")
    node("LuaSource").Text = source
    click("CheckShape")
    check(node("ShapeStatus").Text:find("Looks good", 1, true) ~= nil and context.x2[name] == nil
        and getgenv()._CUSTOM_IMPORT_RUNS == 1, mode .. " checks a script once without registering it")
    click("AddShape")
    check(context.x1.k6 == name and context.loaded_shapes[name] ~= nil and context.x2[name].importRadius == 17,
        mode .. " adds, selects and initializes the pasted shape")
    check(node("ShapeStatus").Text:find("session", 1, true) ~= nil and getgenv()._CUSTOM_IMPORT_RUNS == 2,
        mode .. " reports session-only storage and initializes only once per action")
    check(node("AddShape").Text == "Added" and not node("AddShape").Active and text_button("  " .. name) ~= nil,
        mode .. " prevents duplicate adds and includes the shape in the rebuilt selector")
    check(slider_value("Import radius") == "17", mode .. " builds the imported module's controls with their defaults")
    click("AddShape")
    check(getgenv()._CUSTOM_IMPORT_RUNS == 2, mode .. " ignores a second click on the added draft")
    node("LuaSource"):CaptureFocus()
    click("CloseShapeEditor")
    check(not editor.Visible and not node("LuaSource"):IsFocused(), mode .. " closes the editor and dismisses the keyboard")
    click("CustomShapeEntry")
    check(editor.Visible and node("ShapeName").Text == name and node("LuaSource").Text == source,
        mode .. " retains a closed draft")
    check(context.x4.switch_shape("Black Hole", false), mode .. " can leave a custom shape")
    assert(text_button("  " .. name)).MouseButton1Click:Fire()
    check(context.x1.k6 == name, mode .. " can reselect a custom shape from the actual mode list")

    local files, written = memory_disk()
    local saved_name = "Saved Orbit " .. mode
    node("ShapeName").Text = saved_name
    check(node("AddShape").Active and node("AddShape").Text == "Add & use", mode .. " editing the draft enables another add")
    click("AddShape")
    local path = "GravityShapes/" .. saved_name .. ".lua"
    check(files[path] ~= nil and written() == 1 and context.local_shapes[saved_name] == path and context.x1.k6 == saved_name,
        mode .. " saves the named Lua module and uses it immediately")
    check(node("ShapeStatus").Text:find(path, 1, true) ~= nil, mode .. " reports the actual saved file")
    local old_context, old_entry = context, node("CustomShapeEntry")
    assert(loadfile("main.lua"))()
    context = assert(getgenv()._GRAVITY_CONTEXT)
    check(context ~= old_context and old_context.x6.torn_down and editor._destroyed,
        mode .. " tears down the old editor on reload")
    check(context.local_shapes[saved_name] == path and context.x2[saved_name].importRadius == 17
        and type(context.get_shape(saved_name).f2) == "function" and text_button("  " .. saved_name) ~= nil,
        mode .. " discovers the saved script and its controls at next startup")
    check(context.x2[name] == nil, mode .. " does not misrepresent session-only shapes as persisted")
    old_entry.Activated:Fire()
    check(fixture.find("CustomShapeEditor") == nil, mode .. " a destroyed entry cannot reopen an old editor")
    click("CustomShapeEntry")
    check(node("LuaSource").Text == "" and node("ShapeName").Text == "", mode .. " starts a clean draft in a new session")
    local new_editor = node("CustomShapeEditor")
    context.destroy()
    check(new_editor._destroyed and fixture.input.InputBegan:count() == 0 and fixture.input.InputChanged:count() == 0,
        mode .. " unload removes the editor and session input listeners")
end

print(checks .. " custom shape editor checks passed")
