-- A stubbed Roblox environment: Instances, services, events, and the value types
-- robloxmath does not cover. Enough of the API for System.lua and UI.lua to actually
-- run, which nothing in this suite could do before -- they are the two largest files
-- in the project and had no execution coverage at all.
--
-- Sets the Roblox globals as a side effect and returns the constructors, so a
-- harness can build its own rig on top.
--
--   local env = require("robloxenv")
-- Throwaway: executes the modules nothing in tests/ has ever loaded --
-- System.lua and UI.lua (root + mobilever) -- against a stubbed Roblox env.
-- Newly possible now that luajit parses continue/+= natively.
package.path = "tests/?.lua;" .. package.path
local rm = require("robloxmath")

Vector3, CFrame = rm.Vector3, rm.CFrame
local V3MT = getmetatable(Vector3.new(0,0,0))
local CFMT = getmetatable(CFrame.new(0,0,0))
if not Vector3.one then Vector3.one = Vector3.new(1,1,1) end

-- Luau builtins missing from vanilla
if not math.clamp then math.clamp = function(x,lo,hi) return x<lo and lo or (x>hi and hi or x) end end
if not table.create then table.create = function(n,v) local t={} for i=1,(n or 0) do t[i]=v end return t end end
if not table.clear then table.clear = function(t) for k in pairs(t) do t[k]=nil end end end
if not table.find then table.find = function(t,v) for i,x in ipairs(t) do if x==v then return i end end end end
if not table.freeze then table.freeze = function(t) return t end end

Color3 = { new=function(r,g,b) return {__c3=true,R=r or 0,G=g or 0,B=b or 0} end }
Color3.fromRGB = function(r,g,b) return Color3.new((r or 0)/255,(g or 0)/255,(b or 0)/255) end
Color3.fromHSV = Color3.fromRGB
Vector2 = { new=function(x,y) return {__v2=true,X=x or 0,Y=y or 0} end }
UDim   = { new=function(s,o) return {__udim=true,Scale=s or 0,Offset=o or 0} end }
UDim2  = { new=function(xs,xo,ys,yo) return {__udim2=true,X=UDim.new(xs,xo),Y=UDim.new(ys,yo)} end }
UDim2.fromScale  = function(x,y) return UDim2.new(x,0,y,0) end
UDim2.fromOffset = function(x,y) return UDim2.new(0,x,0,y) end
PhysicalProperties = { new=function(...) return {__pp=true,...} end }
NumberSequenceKeypoint = { new=function(t,v) return {Time=t,Value=v} end }
NumberSequence = { new=function(...) return {__ns=true,...} end }
ColorSequenceKeypoint = { new=function(t,v) return {Time=t,Value=v} end }
ColorSequence = { new=function(...) return {__cs=true,...} end }
NumberRange = { new=function(a,b) return {Min=a,Max=b or a} end }
Rect = { new=function(...) return {...} end }
Ray = { new=function(o,d) return {Origin=o,Direction=d} end }
Region3 = { new=function(...) return {...} end }
TweenInfo = { new=function(...) return {__tween=true,...} end }
Random = { new=function() return { NextNumber=function() return 0.5 end, NextInteger=function(_,a,b) return a or 0 end } end }

-- Enum: permissive, every EnumItem is a distinct sentinel
local enumCache = {}
Enum = setmetatable({}, { __index=function(_,cat)
  enumCache[cat] = enumCache[cat] or setmetatable({}, { __index=function(t,item)
    local e = { __enum=true, Name=item, Value=0, EnumType=cat }
    rawset(t,item,e); return e
  end })
  return enumCache[cat]
end })

-- Universal permissive value: survives arithmetic, concat, calls, indexing.
local ANY
local function num() return 0 end
ANY = setmetatable({}, {
  __index=function() return ANY end, __newindex=function() end,
  __call=function() return ANY end,
  __add=num,__sub=num,__mul=num,__div=num,__mod=num,__pow=num,__unm=num,
  __len=function() return 0 end, __eq=function() return false end,
  __lt=function() return false end, __le=function() return false end,
  __concat=function(a,b) return (type(a)=="string" and a or "")..(type(b)=="string" and b or "") end,
  __tostring=function() return "<ANY>" end,
})

local EVENT_NAMES = {}
local function newEvent()
  local conns = 0
  local ev; ev = {
    Connect=function() conns=conns+1; return { Disconnect=function() end, Connected=true } end,
    Once=function() return { Disconnect=function() end } end,
    Wait=function() return nil end,
    ConnectParallel=function() return { Disconnect=function() end } end,
    Fire=function() end,
  }
  ev.connect = ev.Connect
  return ev
end

local instCount = 0
local function newInstance(class, parent)
  instCount = instCount + 1
  local children, props, events = {}, {}, {}
  local self
  local methods = {}
  self = setmetatable({}, {
    __index=function(_, k)
      if methods[k] then return methods[k] end
      if props[k] ~= nil then return props[k] end
      if EVENT_NAMES[k] then events[k]=events[k] or newEvent(); return events[k] end
      -- unknown: treat as an event if it looks like one, else permissive
      if type(k)=="string" and k:match("^[A-Z]") then
        events[k]=events[k] or newEvent(); return events[k]
      end
      return ANY
    end,
    __newindex=function(_,k,v)
      if k=="Parent" then props.Parent=v; return end
      props[k]=v
    end,
    __tostring=function() return "Instance<"..class..">" end,
  })
  props.ClassName=class; props.Name=class; props.Parent=parent
  props.AbsoluteSize=Vector2.new(800,600); props.AbsolutePosition=Vector2.new(0,0)
  props.Size=UDim2.new(0,100,0,100); props.Position=UDim2.new(0,0,0,0)
  props.Text=""; props.Visible=true; props.Transparency=0; props.BackgroundTransparency=0
  props.CFrame=CFrame.new(0,0,0); props.Velocity=Vector3.zero
  props.AssemblyLinearVelocity=Vector3.zero; props.AssemblyAngularVelocity=Vector3.zero
  props.Anchored=false; props.CanCollide=true; props.Massless=false
  props.CustomPhysicalProperties=nil
  methods.Destroy=function() props.Parent=nil end
  methods.Remove=methods.Destroy
  methods.ClearAllChildren=function() for i=#children,1,-1 do children[i]=nil end end
  methods.GetFullName=function() return class end
  methods.SetPrimaryPartCFrame=function() end
  methods.GetBoundingBox=function() return CFrame.new(0,0,0), Vector3.new(1,1,1) end
  methods.GetExtentsSize=function() return Vector3.new(1,1,1) end
  methods.GetPivot=function() return CFrame.new(0,0,0) end
  methods.GetPlayerFromCharacter=function() return nil end
  methods.GetPartBoundsInBox=function() return {} end
  methods.GetPartsInPart=function() return {} end
  methods.Raycast=function() return nil end
  methods.AddTag=function() end
  methods.HasTag=function() return false end
  methods.GetTags=function() return {} end
  methods.ResetOrientation=function() end
  methods.Activate=function() end
  methods.CaptureFocus=function() end
  methods.ReleaseFocus=function() end
  methods.Play=function() end
  methods.Stop=function() end
  methods.Emit=function() end
  methods.ScaleTo=function() end
  methods.Clone=function() return newInstance(class, nil) end
  methods.IsA=function(_,c) return c==class end
  methods.IsDescendantOf=function() return false end
  methods.GetChildren=function() return children end
  methods.GetDescendants=function() return {} end
  methods.FindFirstChild=function(_,n) for _,c in ipairs(children) do if c.Name==n then return c end end end
  methods.FindFirstChildOfClass=function() return nil end
  methods.FindFirstChildWhichIsA=function() return nil end
  methods.FindFirstAncestorOfClass=function() return nil end
  methods.WaitForChild=function(_,n) return newInstance(n, self) end
  methods.GetPropertyChangedSignal=function() return newEvent() end
  methods.GetAttribute=function() return nil end
  methods.SetAttribute=function() end
  methods.ApplyImpulse=function() end
  methods.GetMass=function() return 1 end
  methods.SetNetworkOwner=function() end
  methods.GetNetworkOwner=function() return nil end
  methods.TweenSize=function() end
  methods.TweenPosition=function() end
  methods.GetTextBoundsAsync=function() return Vector2.new(50,20) end
  methods.SetCore=function() end
  methods.GetCore=function() return nil end
  methods.PivotTo=function() end
  methods.MoveTo=function() end
  methods.BreakJoints=function() end
  -- Children, in insertion order. This used to insert `self` into its *own* children
  -- table, so GetChildren() always came back empty and FindFirstChild could only ever
  -- find the instance itself -- which meant nothing in the suite could see the shape of a
  -- panel it had just built. Registering with the parent is what lets a test assert the
  -- order a UIListLayout is going to lay out, and ordering is the whole reason
  -- UIListLayout.SortOrder exists.
  --
  -- Constructor path only, deliberately: `x.Parent = y` after the fact still just records
  -- the property, exactly as before, so no existing expectation moves.
  rawset(self, "_children", children)
  if parent then
    local pc = rawget(parent, "_children")
    if pc then
      pc[#pc + 1] = self
    end
  end
  return self
end
Instance = { new=function(c,p) return newInstance(c,p) end }

local services = {}
local function svc(name)
  if services[name] then return services[name] end
  local s = newInstance(name, nil)
  services[name] = s
  return s
end
local LocalPlayer = newInstance("Player", nil)
LocalPlayer.Name="Tester"; LocalPlayer.DisplayName="Tester"; LocalPlayer.UserId=1
game = setmetatable({}, { __index=function(_,k)
  if k=="GetService" then return function(_,n) return svc(n) end end
  if k=="HttpGet" then return function() return "" end end
  if k=="Players" then return svc("Players") end
  if k=="Workspace" then return svc("Workspace") end
  if k=="GetObjects" then return function() return {} end end
  return ANY
end })
workspace = svc("Workspace")
svc("Players").LocalPlayer = LocalPlayer
svc("Players").GetPlayers = function() return { LocalPlayer } end
svc("Players").LocalPlayer.GetMouse = function() return newInstance("Mouse", nil) end
svc("TweenService").Create = function() return { Play=function() end, Cancel=function() end, Completed=newEvent() } end
svc("HttpService").JSONEncode = function(_,t) return "{}" end
svc("HttpService").JSONDecode = function() return {} end
svc("HttpService").UrlEncode = function(_,s) return tostring(s) end
svc("HttpService").GenerateGUID = function() return "guid" end
svc("ContextActionService").BindAction = function() end
svc("ContextActionService").UnbindAction = function() end
svc("UserInputService").TouchEnabled = false
svc("UserInputService").KeyboardEnabled = true
svc("UserInputService").GetMouseLocation = function() return Vector2.new(400,300) end


-- give the local player a real Character (shapes cast from HumanoidRootPart)
local char = newInstance("Model", nil)
char.Name = "Tester"
local hrp = newInstance("Part", char); hrp.Name = "HumanoidRootPart"
hrp.Position = Vector3.new(0,10,0); hrp.CFrame = CFrame.new(0,10,0)
hrp.Size = Vector3.new(2,2,1)
local hum = newInstance("Humanoid", char); hum.Name = "Humanoid"
local head = newInstance("Part", char); head.Name = "Head"
head.Position = Vector3.new(0,11,0); head.CFrame = CFrame.new(0,11,0)
rawset(char, "_kids", true)
local realFFC = { HumanoidRootPart=hrp, Humanoid=hum, Head=head, UpperTorso=hrp, Torso=hrp }
getmetatable(char).__index = function(_, k)
  if realFFC[k] then return realFFC[k] end
  if k=="FindFirstChild" then return function(_,n) return realFFC[n] end end
  if k=="FindFirstChildOfClass" then return function(_,c) return c=="Humanoid" and hum or nil end end
  if k=="FindFirstChildWhichIsA" then return function(_,c) return c=="Humanoid" and hum or nil end end
  if k=="GetChildren" then return function() return {hrp,hum,head} end end
  if k=="IsA" then return function(_,c) return c=="Model" end end
  if k=="Name" then return "Tester" end
  if k=="PrimaryPart" then return hrp end
  if k=="Parent" then return workspace end
  if k=="Destroy" then return function() end end
  if k=="GetPivot" then return function() return CFrame.new(0,10,0) end end
  return ANY
end
LocalPlayer.Character = char

task = {
  wait=function() return 0 end, delay=function() end,
  spawn=function(f,...) return nil end, defer=function() end, cancel=function() end,
}
function typeof(v)
  local t=type(v)
  if t=="table" then
    local mt=getmetatable(v)
    if mt==V3MT then return "Vector3" end
    if mt==CFMT then return "CFrame" end
    if rawget(v,"__c3") then return "Color3" end
    if rawget(v,"__v2") then return "Vector2" end
    if rawget(v,"__udim") then return "UDim" end
    if rawget(v,"__udim2") then return "UDim2" end
    if rawget(v,"__enum") then return "EnumItem" end
    if rawget(v,"__tween") then return "TweenInfo" end
    return "table"
  end
  return t
end
function tick() return 0 end
function time() return 0 end
function warn(...) end
function gethiddenproperty() return nil, false end
function sethiddenproperty() return false end
function getgenv() return _G end
function cloneref(x) return x end
function setthreadidentity() end
function isfolder() return false end
function makefolder() end
function listfiles() return {} end
function readfile() return nil end
function writefile() end
function isfile() return false end
function setfpscap() end
function firetouchinterest() end
function getconnections() return {} end


-- ---- extra Roblox value types the big shapes need -------------------------
local CFMT2 = getmetatable(CFrame.new(0,0,0))
local function cross(a,b)
  return Vector3.new(a.Y*b.Z-a.Z*b.Y, a.Z*b.X-a.X*b.Z, a.X*b.Y-a.Y*b.X)
end
CFrame.fromMatrix = function(pos, vx, vy, vz)
  vx = vx or Vector3.new(1,0,0); vy = vy or Vector3.new(0,1,0)
  vz = vz or cross(vx, vy)
  return setmetatable({ p = pos or Vector3.zero, r = {
    vx.X, vy.X, vz.X,
    vx.Y, vy.Y, vz.Y,
    vx.Z, vy.Z, vz.Z } }, CFMT2)
end
CFrame.Angles = function(rx, ry, rz)
  local X = CFrame.fromAxisAngle(Vector3.new(1,0,0), rx or 0)
  local Y = CFrame.fromAxisAngle(Vector3.new(0,1,0), ry or 0)
  local Z = CFrame.fromAxisAngle(Vector3.new(0,0,1), rz or 0)
  return X * Y * Z
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromEulerAnglesYXZ = function(rx,ry,rz) return CFrame.Angles(rx,ry,rz) end
CFrame.lookAt = function(from, to, up)
  up = up or Vector3.new(0,1,0)
  local dir = to - from
  local m = dir.Magnitude
  if m < 1e-9 then return CFrame.new(from.X, from.Y, from.Z) end
  local back = Vector3.new(-dir.X/m, -dir.Y/m, -dir.Z/m)
  local right = cross(up, back)
  local rm = right.Magnitude
  if rm < 1e-9 then
    right = cross(Vector3.new(0,0,1), back); rm = right.Magnitude
    if rm < 1e-9 then return CFrame.new(from.X, from.Y, from.Z) end
  end
  right = Vector3.new(right.X/rm, right.Y/rm, right.Z/rm)
  local trueUp = cross(back, right)
  return CFrame.fromMatrix(from, right, trueUp, back)
end

RaycastParams = { new = function()
  local t = { FilterType=nil, FilterDescendantsInstances={}, IgnoreWater=false,
              CollisionGroup="Default", RespectCanCollide=false, BruteForceAllSlow=false }
  return setmetatable(t, { __index=function() return nil end, __newindex=function(tt,k,v) rawset(tt,k,v) end })
end }
OverlapParams = RaycastParams

-- a real camera and a real mouse.Hit, so aim code takes its normal path
local cam = newInstance("Camera", nil)
cam.CFrame = CFrame.lookAt(Vector3.new(0,12,-20), Vector3.new(0,10,0))
cam.ViewportSize = Vector2.new(1280,720)
getmetatable(cam).__index = (function(prev)
  return function(t,k)
    if k=="CFrame" then return CFrame.lookAt(Vector3.new(0,12,-20), Vector3.new(0,10,0)) end
    if k=="ViewportSize" then return Vector2.new(1280,720) end
    if k=="ViewportPointToRay" then
      return function() return { Origin=Vector3.new(0,12,-20), Direction=Vector3.new(0,-0.2,1) } end
    end
    if k=="ScreenPointToRay" then
      return function() return { Origin=Vector3.new(0,12,-20), Direction=Vector3.new(0,-0.2,1) } end
    end
    if k=="WorldToViewportPoint" then return function() return Vector3.new(640,360,10), true end end
    if k=="WorldToScreenPoint" then return function() return Vector3.new(640,360,10), true end end
    return prev(t,k)
  end
end)(getmetatable(cam).__index)
workspace.CurrentCamera = cam
workspace.Raycast = function(_, origin, dir)
  -- a real baseplate hit under the core; returns nil for upward rays (open sky)
  if dir and dir.Y and dir.Y > 0 then return nil end
  return { Position=Vector3.new(0,0,0), Normal=Vector3.new(0,1,0),
           Instance=newInstance("Part",nil), Distance=10, Material=Enum.Material.Plastic }
end
workspace.Gravity = 196.2
local realMouse = newInstance("Mouse", nil)
getmetatable(realMouse).__index = (function(prev)
  return function(t,k)
    if k=="Hit" then return CFrame.new(0,10,0) end
    if k=="Target" then return nil end
    if k=="UnitRay" then return { Origin=Vector3.new(0,12,-20), Direction=Vector3.new(0,-0.2,1) } end
    if k=="X" then return 640 end
    if k=="Y" then return 360 end
    return prev(t,k)
  end
end)(getmetatable(realMouse).__index)
LocalPlayer.GetMouse = function() return realMouse end



-- Roblox globals/methods the engine touches
function settings()
  return { Physics = setmetatable({}, {__index=function() return false end, __newindex=function() end}),
           Rendering = setmetatable({}, {__index=function() return false end, __newindex=function() end}) }
end
function UserSettings()
  return { GetService = function() return setmetatable({}, {__index=function() return false end, __newindex=function() end}) end }
end
svc("HttpService").RequestAsync = function() return { Success=false, StatusCode=0, Body="", Headers={} } end
svc("HttpService").GetAsync = function() return "" end
workspace.FallenPartsDestroyHeight = -500
workspace.StreamingEnabled = false

-- Vector3 methods robloxmath omits
local V3MTx = getmetatable(Vector3.new(0,0,0))
V3MTx.Lerp = function(a, b, t)
  t = t or 0
  return Vector3.new(a.X+(b.X-a.X)*t, a.Y+(b.Y-a.Y)*t, a.Z+(b.Z-a.Z)*t)
end
V3MTx.FuzzyEq = function(a,b,e)
  e = e or 1e-5
  return math.abs(a.X-b.X)<=e and math.abs(a.Y-b.Y)<=e and math.abs(a.Z-b.Z)<=e
end
V3MTx.Angle = function(a,b)
  local ma, mb = a.Magnitude, b.Magnitude
  if ma<1e-9 or mb<1e-9 then return 0 end
  local c = (a.X*b.X+a.Y*b.Y+a.Z*b.Z)/(ma*mb)
  return math.acos(c < -1 and -1 or (c > 1 and 1 or c))
end
V3MTx.Max = function(a,b) return Vector3.new(math.max(a.X,b.X),math.max(a.Y,b.Y),math.max(a.Z,b.Z)) end
V3MTx.Min = function(a,b) return Vector3.new(math.min(a.X,b.X),math.min(a.Y,b.Y),math.min(a.Z,b.Z)) end

return {
	svc = svc,
	newInstance = newInstance,
	newEvent = newEvent,
	LocalPlayer = LocalPlayer,
	ANY = ANY,
}
