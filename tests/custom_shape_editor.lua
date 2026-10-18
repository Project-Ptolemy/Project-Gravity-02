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

-- Observe input, viewport resizing and keyboard changes without pretending the
-- fixture can render Roblox text or calculate UIListLayout geometry.
local factory = Instance.new
Instance.new = function(class, parent)
    local item = factory(class, parent)
    local signals = {}
    local meta = getmetatable(item)
    local write, get_signal = meta.__newindex, item.GetPropertyChangedSignal
    meta.__newindex = function(self, key, value)
        local previous = signals[key] and self[key]
        write(self, key, value)
        if signals[key] and previous ~= value then signals[key]:Fire() end
    end
    rawset(item, "GetPropertyChangedSignal", function(self, property)
        if property == "Text" or property == "AbsoluteSize" or property == "AbsolutePosition" then
            signals[property] = signals[property] or fixture.signal()
            return signals[property]
        end
        return get_signal(self, property)
    end)
    item.Destroying:Connect(function() for _, signal in pairs(signals) do signal:disconnect() end end)
    if class == "TextBox" then
        item.Focused, item.FocusLost = fixture.signal(), fixture.signal()
        local focused = false
        rawset(item, "IsFocused", function() return focused end)
        rawset(item, "CaptureFocus", function() focused = true; item.Focused:Fire() end)
        rawset(item, "ReleaseFocus", function(_, enter) focused = false; item.FocusLost:Fire(enter) end)
        item.Destroying:Connect(function() item.Focused:disconnect(); item.FocusLost:disconnect() end)
    end
    return item
end

local keyboardSignals = {}
rawset(fixture.input, "GetPropertyChangedSignal", function(_, property)
    keyboardSignals[property] = keyboardSignals[property] or fixture.signal()
    return keyboardSignals[property]
end)
local function keyboard(visible, top, height)
    fixture.input.OnScreenKeyboardVisible = visible
    fixture.input.OnScreenKeyboardPosition = Vector2.new(0, top)
    fixture.input.OnScreenKeyboardSize = Vector2.new(320, height)
    for _, signal in pairs(keyboardSignals) do signal:Fire() end
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
    keyboard(false, 0, 0)
    getclipboard = nil
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
    check(node("CheckShape").Visible and not node("AddShape").Visible and not node("PasteShape").Visible,
        mode .. " offers a review step and native paste when clipboard access is unavailable")
    check(not node("LuaSource"):IsFocused() and not node("ShapeName"):IsFocused(), mode .. " opening does not summon the touch keyboard")
    click("AddShape")
    check(context.x1.k6 == initial_shape and not node("ShapeStatus").Visible, mode .. " cannot add an unreviewed draft")
    click("CheckShape")
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
    check(node("ShapeReview").Visible and not node("ImportForm").Visible and node("ReviewShapeName").Text == name
        and node("ReviewControls").Text:find("Import radius", 1, true) and node("AddShape").Visible,
        mode .. " summarizes the checked name and actual module controls before adding")
    click("AddShape")
    check(context.x1.k6 == name and context.loaded_shapes[name] ~= nil and context.x2[name].importRadius == 17,
        mode .. " adds, selects and initializes the pasted shape")
    check(node("ShapeStatus").Text:find("session", 1, true) ~= nil and getgenv()._CUSTOM_IMPORT_RUNS == 2,
        mode .. " reports session-only storage and initializes only once per action")
    check(node("ShapeAdded").Visible and node("AnotherShape").Visible and node("DoneShapeEditor").Visible
        and not node("AddShape").Active and text_button("  " .. name) ~= nil,
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
    check(node("CheckShape").Visible and not node("AddShape").Active, mode .. " editing the draft requires a fresh review")
    click("CheckShape")
    click("BackShapeEditor")
    check(node("ImportForm").Visible and node("LuaSource").Text == source and node("ShapeName").Text == saved_name,
        mode .. " back from review retains both fields")
    click("CheckShape")
    click("AddShape")
    local path = "GravityShapes/" .. saved_name .. ".lua"
    check(files[path] ~= nil and written() == 1 and context.local_shapes[saved_name] == path and context.x1.k6 == saved_name,
        mode .. " saves the named Lua module and uses it immediately")
    check(node("ShapeStatus").Text:find(path, 1, true) ~= nil, mode .. " reports the actual saved file")
    click("AnotherShape")
    check(node("ImportForm").Visible and node("ShapeName").Text == "" and node("LuaSource").Text == "",
        mode .. " starts another import only after an explicit action")

    getclipboard = function() return "-- Project Gravity Shape Builder \194\183 Clipboard Orbit\n" .. source end
    click("CloseShapeEditor"); click("CustomShapeEntry")
    check(node("PasteShape").Visible, mode .. " shows the clipboard action when supported")
    click("PasteShape")
    local pasted = node("LuaSource").Text
    check(node("ShapeName").Text == "Clipboard Orbit" and pasted:find(source, 1, true),
        mode .. " pastes the complete export and suggests its project name")
    getclipboard = function() error("Unavailable") end
    click("PasteShape")
    check(node("LuaSource").Text == pasted and node("ShapeStatus").Text:find("Clipboard", 1, true),
        mode .. " a clipboard failure keeps the previous draft and explains native paste")
    node("EditorFields").CanvasPosition = Vector2.new(0, 190)
    node("LuaSource").Text = pasted .. "\n-- edited"
    check(node("EditorFields").CanvasPosition.Y == 190, mode .. " typing does not jump the scroller back to the top")
    click("SelectShapeSource")
    check(node("LuaSource"):IsFocused() and node("LuaSource").SelectionStart == 1
        and node("LuaSource").CursorPosition == #node("LuaSource").Text + 1,
        mode .. " select all focuses and selects the full source")
    node("LuaSource"):ReleaseFocus()
    node("ShapeName"):CaptureFocus(); node("ShapeName"):ReleaseFocus(true)
    check(node("LuaSource"):IsFocused(), mode .. " the name keyboard action advances to the Lua field")
    node("LuaSource"):ReleaseFocus()
    node("EditorFields").AbsolutePosition, node("EditorFields").AbsoluteSize = Vector2.new(16, 100), Vector2.new(300, 300)
    node("EditorFields").CanvasPosition = Vector2.new(0, 40)
    node("ShapeCodeScroll").AbsolutePosition, node("ShapeCodeScroll").AbsoluteSize = Vector2.new(16, 150), Vector2.new(300, 160)
    node("LuaSource"):CaptureFocus()
    check(node("EditorFields").CanvasPosition.Y == 40, mode .. " focusing a fully visible script does not jump the outer scroller")
    node("EditorFields").AbsoluteSize = Vector2.new(300, 100)
    check(node("EditorFields").CanvasPosition.Y == 90, mode .. " a shrinking viewport brings the focused script above the keyboard")
    node("LuaSource"):ReleaseFocus()

    for _, viewport in ipairs({ { 320, 568 }, { 390, 844 }, { 568, 320 }, { 844, 350 }, { 1280, 900 } }) do
        editor.AbsoluteSize = Vector2.new(viewport[1], viewport[2])
        local dialog = node("CustomShapeDialog")
        check(dialog.Position.X.Offset >= 0 and dialog.Position.Y.Offset >= 0
            and dialog.Position.X.Offset + dialog.Size.X.Offset <= viewport[1]
            and dialog.Position.Y.Offset + dialog.Size.Y.Offset <= viewport[2],
            mode .. " dialog fits " .. viewport[1] .. "x" .. viewport[2])
        for _, target in ipairs({ "CloseShapeEditor", "CheckShape", "AddShape", "AnotherShape", "DoneShapeEditor" }) do
            local minimum = target == "CloseShapeEditor" and 44 or (mobile and 44 or 36)
            check(node(target).Size.Y.Offset >= minimum, mode .. " retains an accessible target for " .. target)
        end
        check(node("EditorFields").Size.Y.Offset > 0 and dialog.Size.Y.Offset <= 620,
            mode .. " keeps the editor compact with a usable scrolling body")
        local landscape = viewport[1] >= 532 and viewport[2] < 480
        check((node("ImportDetails").Size.X.Scale < 1) == landscape
            and (node("SourceGroup").Size.X.Scale < 1) == landscape,
            mode .. " lays out the name beside the script when landscape has enough width")
        check(node("EditorActions").Size.Y.Offset >= node("CheckShape").Position.Y.Offset + node("CheckShape").Size.Y.Offset,
            mode .. " contains the action target inside its fixed footer")
    end
    editor.AbsoluteSize, editor.AbsolutePosition = Vector2.new(844, 350), Vector2.new(0, 36)
    keyboard(true, 216, 134)
    local dialog, fields = node("CustomShapeDialog"), node("EditorFields")
    check(dialog.Position.Y.Offset + dialog.Size.Y.Offset <= 180 and not node("ImportSteps").Visible
        and fields.Size.Y.Offset > 0 and node("EditorActions").Visible,
        mode .. " keeps actions above a landscape keyboard while leaving a scrollable body")
    keyboard(true, 130, 220)
    check(dialog.Position.Y.Offset + dialog.Size.Y.Offset <= 94 and fields.Size.Y.Offset > 0,
        mode .. " an unusually tall keyboard never pushes the dialog behind it")
    keyboard(false, 0, 0)
    check(node("EditorActions").Visible, mode .. " keyboard dismissal restores the action row")
    fixture.input.InputBegan:Fire({ KeyCode = Enum.KeyCode.Escape }, false)
    check(not editor.Visible and not node("LuaSource"):IsFocused(), mode .. " Escape closes the editor and releases focus")
    click("CustomShapeEntry")
    check(node("LuaSource").Text == pasted .. "\n-- edited", mode .. " keyboard and viewport changes preserve the draft")
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
    for _, signal in pairs(keyboardSignals) do check(signal:count() == 0, mode .. " unload disconnects keyboard geometry listeners") end
end

-- Module execution and clipboard helpers can yield. A result belongs to the
-- captured input, and must not overwrite newer text or enable a stale add.
do
    local gui = Instance.new("ScreenGui", game:GetService("CoreGui"))
    local context = { x6 = {}, v1 = fixture.input, custom_shapes = {} }
    local editor = assert(loadfile("CustomShapeEditor.lua"))()(context, gui)
    editor.open()
    node("ShapeName").Text, node("LuaSource").Text = "Before", source
    local validates = 0
    context.custom_shapes.validate = function(name, source)
        validates = validates + 1
        check(not node("ShapeName").TextEditable and not node("LuaSource").TextEditable,
            "validation locks fields while module execution is in progress")
        click("CheckShape")
        node("ShapeName").Text = "Newer draft"
        return true, { name = name, source = source, module = {} }
    end
    click("CheckShape")
    check(validates == 1 and node("ImportForm").Visible and not node("AddShape").Active
        and node("ShapeName").Text == "Newer draft" and node("ShapeStatus").Text:find("changed", 1, true),
        "a changed draft cannot inherit another draft's validation or start a second check")
    context.custom_shapes.validate = function(name, source)
        return true, { name = name, source = source, module = {} }
    end
    click("CheckShape")
    local adds = 0
    context.custom_shapes.add = function(name, source)
        adds = adds + 1
        click("AddShape")
        node("LuaSource").Text = source .. "\n-- new draft while adding"
        return true, { name = name, message = "Added to this session.", switched = true }
    end
    click("AddShape")
    check(adds == 1 and node("ImportForm").Visible and node("LuaSource").Text:find("new draft", 1, true)
        and node("ShapeStatus").Text:find("newer draft", 1, true),
        "an add finishes once and preserves newer draft text")
    getclipboard = function()
        node("LuaSource").Text = "-- text entered during clipboard read"
        return source
    end
    editor.open(); click("PasteShape")
    check(node("LuaSource").Text == "-- text entered during clipboard read", "a delayed clipboard read cannot replace newer text")
    gui:Destroy()
    for _, signal in pairs(keyboardSignals) do check(signal:count() == 0, "direct editor destruction releases keyboard listeners") end
end

print(checks .. " custom shape editor checks passed")
