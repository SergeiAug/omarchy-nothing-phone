local rules, callbacks, windows, calls, config = {}, {}, {}, {}, {}
local function dispatcher(name)
 return function(args) return function()
  table.insert(calls, {name=name,args=args})
  local w=windows[1]
  if name=='set_prop' and args.prop=='max_size' then
   local x,y=args.value:match('([%d.]+) ([%d.]+)')
   w.size={x=math.min(w.size.x,tonumber(x)),y=math.min(w.size.y,tonumber(y))}
  end
 end end
end
hl={monitor=function() end,config=function(c) config=c end,
 window_rule=function(r) table.insert(rules,r) end,
 on=function(event,callback) callbacks[event]=callback end,
 get_windows=function() return windows end,
 dsp={window={set_prop=dispatcher('set_prop'),move=dispatcher('move')}}}
dofile(arg[1])
assert(config.input.kb_layout=='us,ru' and config.input.touchdevice.output=='DSI-1')
local function tagged(tags,tag)
 for _,v in ipairs(tags) do if v==tag then return true end end
 return false
end
local function map(class,initialFloat,modal,portal,xdg)
 local state={float=initialFloat,maximize=false,workspace='parent',size='875 600'}
 local tags={'floating-window'}
 local currentFloat=initialFloat
 local function apply(recheck)
 for _,r in ipairs(rules) do
  -- v0.56.2 only rechecks rules that depend on changed tags/content.
  if not recheck or r.match.tag then
  local m=r.match
  local match=true
  if m.class then match=(portal and m.class:find('portal')) or (class=='gcr-prompter' and m.class:find('gcr%-prompter')) or false end
  if m.float~=nil then match=match and m.float==currentFloat end
  if m.modal~=nil then match=match and m.modal==modal end
  if m.xdg_tag then match=match and xdg end
  if m.tag then
   local neg=m.tag:sub(1,9)=='negative:'
   match=match and (tagged(tags,neg and m.tag:sub(10) or m.tag)~=neg)
  end
  if match then
   for k,v in pairs(r) do if k~='match' and k~='tag' then state[k]=v end end
   if r.tag then
    if r.tag:sub(1,1)=='+' then table.insert(tags,r.tag:sub(2))
    else for i=#tags,1,-1 do if tags[i]==r.tag:sub(2) then table.remove(tags,i) end end end
   end
  end
 end
 end
 end
 apply(false)
 currentFloat=state.float
 apply(true)
 return state,tags
end
for _,class in ipairs({'foot','org.omarchy.terminal','org.omarchy.about','Nautilus'}) do
 local s,t=map(class,false,false,false)
 assert(s.float==false and s.maximize and s.workspace=='empty',class)
 assert(not tagged(t,'floating-window'))
end
for _,case in ipairs({{true,false,false},{false,true,false},{false,false,true},{false,false,false,true}}) do
 local s,t=map('dialog',table.unpack(case))
 assert(s.float and not s.maximize and s.workspace=='unset' and s.size=='')
 assert(tagged(t,'spacewar-dialog'))
end
local s,t=map('gcr-prompter',false,false,false)
assert(s.float and not s.maximize and s.workspace=='unset')
local monitor={position={x=0,y=0},size={width=1080,height=2400},scale=2,
 reserved={top=56,bottom=360,left=0,right=0}}
for _,size in ipairs({{x=300,y=200},{x=900,y=1400}}) do
 windows={{address='0x123',mapped=true,floating=true,tags={'spacewar-dialog*'},monitor=monitor,size=size}}
 calls={}; callbacks['window.open']()
 local w=windows[1]; local pos=calls[#calls].args
 assert(w.size.x<=532 and w.size.y<=776)
 assert(pos.x>=4 and pos.y>=60 and pos.y+w.size.y<=836)
 if size.x==300 then assert(w.size.x==300 and w.size.y==200) end
 monitor.reserved.bottom=500
 calls={}; spacewar_fit_dialogs()
 assert(w.size.y<=636 and calls[#calls].args.y+w.size.y<=696)
 monitor.reserved.bottom=360
end
print('PASS: top-level desktop floats, parent/fixed/modal/portal dialogs, reserved-area resize and centering')
