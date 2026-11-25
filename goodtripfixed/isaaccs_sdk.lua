--[[
IsaacCS Mod SDK（isaaccs_sdk.lua）

这是什么
  第三方 Mod 接入"以撒联机"用的单文件 SDK。Mod 把它复制进自己的目录，在 main.lua 顶部用
  include 引入本文件，取得 IsaacCS 表，再对 RegisterMod 返回的 Mod 对象调用
  IsaacCS.Declare 登记版本。之后用 IsaacCS.State / EntityData / EntityState 声明
  "客机绘制要读的状态"，用 IsaacCS.Intent 声明"客机 UI 要让 Host 执行的操作"。
  完整说明见 docs/mod-api.md。

本文件只是一层薄壳
  联机层（zhlIsaacCS.dll）在任何 Mod 加载之前，就把自己的 IsaacCS 实现放进了全局。
  本文件被引入时：
  1. 全局已有联机层的实现，且版本不低于本 SDK：直接返回它，本文件其余代码都不生效。
  2. 全局已有联机层的实现，但版本比本 SDK 旧：把它缺少的函数补成本文件的单机版本，
     并让本 Mod 的 Declare 要求本 SDK 的版本。联机层不支持时，该 Mod 联机时按未声明处理，
     大厅提示更新联机层；单机照常可玩。
  3. 没有安装联机层：安装本文件的单机实现。它只提供单机下需要的行为（意图在本机执行、
     查询返回单机的值），不检查声明。声明写错要装上联机层才会报错，所以 Mod 作者
     测试时应安装联机层。

单机实现的行为以 docs/mod-api.md 4.6 节为准，须与联机层在"装了但没有开启联机会话"时一致。
本文件发布后会被复制进各个 Mod 并长期留在那里，所以只放最少的逻辑：已发布函数的签名和
单机语义不再改动，新功能只以新增函数的形式加入，同时把 version 加 1。
]]

-- 以下 LuaCATS 注解只供 lua-language-server 补全和检查，不影响运行。

--[[
标量类型名。括号里是线上定长字节数：bool(1) int(4，i32) float(4，f32) number(8，f64)
vector(8) color(28) kcolor(16) entity(2，实体成员号) player(1，参与者序号)。
]]
---@alias IsaacCSScalar "bool"|"int"|"float"|"number"|"vector"|"color"|"kcolor"|"entity"|"player"
--[[
值类型：标量名，或只含一个键的表，键名是容器种类：
  string  字符串，max 为字节上限（不超过 1024）
  list    从 1 开始的连续数组，of 为元素类型，max 为项数上限（不超过 65535）
  map     字典，key 为 "string" 或 "int"，of 为值类型，max 为项数上限，
          keymax 为字符串键的字节上限（默认 64）
  struct  固定字段的表，值为"字段名 → 类型"，至少一个字段，字段可以为 nil
单个值编码后的最坏长度不超过 64 KiB。
]]
---@alias IsaacCSType IsaacCSScalar|{string:{max:integer}}|{list:{of:IsaacCSType,max:integer}}|{map:{key:"string"|"int",of:IsaacCSType,max:integer,keymax:integer?}}|{struct:table<string,IsaacCSType>}
-- 实体筛选条件。只有 type 必填；variant、subtype 省略表示任意。
---@alias IsaacCSFilter {type:integer,variant:integer?,subtype:integer?}
-- IsaacCS.State 的选项。scope 默认 "global"，rate 默认 "world"；private 只能用于 "player"。
---@alias IsaacCSState {type:IsaacCSType,scope:("global"|"player")?,private:boolean?,rate:("world"|"low"|"mark")?,get:function?,set:function?,reset:function?}
-- IsaacCS.EntityState 的选项。get(ent) 和 set(ent, v) 必填。
---@alias IsaacCSEntityState {type:IsaacCSType,filter:IsaacCSFilter,rate:("world"|"low"|"mark")?,get:function,set:function,reset:function?}
-- IsaacCS.Intent 的选项。handler(player, args) 只在 Host 执行，返回 ok[, result]。
---@alias IsaacCSIntent {args:IsaacCSType,handler:fun(player:EntityPlayer,args:any):boolean,any}
-- IsaacCS.AddCallback 可用的联机层回调名，也可写成 IsaacCS.CLIENT_xxx。
---@alias IsaacCSCallback "CLIENT_SCENE_STARTED"|"CLIENT_SCENE_ENDED"|"CLIENT_ENTITY_INSTALLED"|"CLIENT_ENTITY_REMOVED"|"CLIENT_STATE_CHANGED"|"CLIENT_INTENT_RESULT"

-- 本 SDK 的接口版本（即 IsaacCS.api）。只增不减；新增函数时加 1。
local version = 1
-- 全局里已经存在的 IsaacCS（联机层的实现，或别的 Mod 先引入的某个版本的本 SDK）。
local existing = rawget(_G, "IsaacCS")
-- 已存在实现的内部信息：native 为 true 表示联机层的实现；不是 IsaacCS 的表则为 nil/false。
local previous = type(existing) == "table" and existing._isaaccs
-- 全局已有同版本或更新的实现（联机层的，或别的 Mod 带的更新的 SDK），直接用它。
if previous and existing.api >= version then return existing end

-- 联机层回调名，作为常量挂到 IsaacCS 上。单机时只有 CLIENT_INTENT_RESULT 会触发。
local names = { "CLIENT_SCENE_STARTED", "CLIENT_SCENE_ENDED", "CLIENT_ENTITY_INSTALLED",
    "CLIENT_ENTITY_REMOVED", "CLIENT_STATE_CHANGED", "CLIENT_INTENT_RESULT" }
--[[
单机实现的状态，全部 Mod 共用。别的 Mod 先引入了旧版本 SDK 的单机实现时沿用它的状态，
已登记的意图和回调不会丢；所以以后的 SDK 版本必须保持这个结构兼容。
  entries[mod]  每个 Mod 的登记项：
                  intents   "意图名 → handler"
                  callbacks "回调名 → 函数数组"
                  results, deliverCallback  待派发的意图结果和派发用的回调（见 SendIntent）
  sequence      意图调用序号的计数器
]]
local state = previous and not previous.native and previous.state or { entries = {}, sequence = 0 }
--[[
本文件提供的 IsaacCS 表。替换旧版本的单机实现时原地改写旧表，
这样先引入旧版的 Mod 手里的引用也能用到新函数；其余情况新建一张表。
]]
---@class IsaacCS
---@field api integer 当前实现的 SDK 接口版本
local CS = previous and not previous.native and existing or {}
CS.api = version
for _, name in ipairs(names) do CS[name] = name end

-- Mod 被卸载（如 luamod 重载）时删除它的登记项。每个 Mod 都会收到该回调，只在卸载的正是自己时删除。
---@param owner table 注册此回调的 Mod
---@param unloaded table 正在卸载的 Mod
local function forget(owner, unloaded)
    if owner == unloaded then state.entries[owner] = nil end
end

-- 取得某个 Mod 的登记项，没有就新建，并登记卸载时的清理。
---@param mod table RegisterMod 返回的 Mod 对象
---@return table 登记项
local function entryOf(mod)
    local entry = state.entries[mod]
    if not entry then
        entry = { intents = {}, callbacks = {} }
        state.entries[mod] = entry
        if ModCallbacks.MC_PRE_MOD_UNLOAD then mod:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, forget) end
    end
    return entry
end

-- 判断参数是不是 RegisterMod 返回的 Mod 对象。不是时单机实现直接忽略这次调用。
---@param mod any
---@return boolean
local function isMod(mod)
    return type(mod) == "table" and type(mod.AddCallback) == "function"
end

--[[
声明本 Mod 支持联机，并登记版本。每个 Mod 调用一次，只能在加载期调用。
调用过 Declare 的 Mod 才算"已声明"；启用了有 main.lua 却没有声明的 Mod，联机时拒绝连接。
info 可以只写版本字符串，也可以写成带 version 和 api 两个字段的表。
version 进入握手清单，两端必须相等。api 是 Mod 需要的 SDK 接口版本，省略时取本 SDK 的版本。
单机：什么也不做。
]]
---@param mod table RegisterMod 返回的 Mod 对象
---@param info string|{version:string,api:integer?} 版本字符串，或带 version、api 字段的表
function CS.Declare(mod, info) end

--[[
声明一项要同步给客机的状态：整局一份（scope 为 "global"，默认）或每个参与者一份（scope 为 "player"）。
只能在加载期调用。选项：
  type     值类型，必填
  private  仅 player 可用。为 true 时只发给该参与者本人，其他客机上读到的是默认值
  rate     Host 读取频率："world"（默认，约 30Hz）、"low"（约 10Hz）、"mark"（只在 MarkDirty 后读）
  get      Host 上读值：global 不带参数，player 收到该参与者的身体。省略时读 mod[name]
  set      客机上写值：global 收到新值，player 收到身体和新值。省略时按"默认写回"写 mod[name]
           （表会原地合并，保留未声明的字段和元表）。完整基线会以相同的值再次调用，不要带副作用
  reset    客机离开场景、换局或会话结束时调用，用于清理
单机：什么也不做，不调用 get/set/reset。
]]
---@param mod table RegisterMod 返回的 Mod 对象
---@param name string 声明名称，同一 Mod 内不能重复；也是默认读写 mod[name] 用的键
---@param options IsaacCSState
function CS.State(mod, name, options) end

--[[
声明：符合筛选条件的实体，把 GetData() 里列出的键同步给客机。只能在加载期调用。
fields 的每个键各成一条声明，至少一项。Host 读实体 GetData() 中的该键，客机按"默认写回"写
本地实体 GetData() 中的同一个键。GetData() 是所有 Mod 共用的表，键名建议带 Mod 前缀。
单机：什么也不做。
]]
---@param mod table RegisterMod 返回的 Mod 对象
---@param filter IsaacCSFilter 实体筛选条件
---@param fields table<string,IsaacCSType> 键名 → 值类型
function CS.EntityData(mod, filter, fields) end

--[[
声明一项实体级状态，数据放在 Mod 自己的表里时使用（放在 GetData() 里的用 EntityData）。
只能在加载期调用。filter、type、get、set 必填；rate、reset 可选。
get 收到实体，set 收到实体和新值，拿到的都是本端的实体对象，可以用 GetPtrHash 的结果做键：
两端的实体由联机层按成员号对应，Mod 不需要自己换键。
单机：什么也不做。
]]
---@param mod table RegisterMod 返回的 Mod 对象
---@param name string 声明名称，同一 Mod 内不能重复
---@param options IsaacCSEntityState
function CS.EntityState(mod, name, options) end

--[[
声明一个"意图"：客机 UI 想改变游戏状态时，交给 Host 执行的操作。只能在加载期调用，两端都要声明。
  args     参数的值类型
  handler  只在 Host 执行（单机时在本机执行），收到发起者当前的身体和参数。
           自己检查操作是否合法，返回 ok 和可选的结果；抛错视为失败
发起用 IsaacCS.SendIntent，结果通过 CLIENT_INTENT_RESULT 回到发起端。
单机：记下 handler，供 SendIntent 调用。
]]
---@param mod table RegisterMod 返回的 Mod 对象
---@param name string 意图名称，同一 Mod 内不能重复
---@param options IsaacCSIntent
function CS.Intent(mod, name, options)
    if not isMod(mod) or type(options) ~= "table" or type(options.handler) ~= "function" then return end
    entryOf(mod).intents[name] = options.handler
end

--[[
声明 Mod 自定义的键盘按键，联机时客机会采样这些按键并随输入上传给 Host，
Host 的玩法代码用 IsKeyPressed / IsKeyTriggered 查询。客机 UI 自己读的本机按键不需要声明。
只能在加载期调用，每个 Mod 只能调用一次。buttons 是非空、连续、不重复的数组，键值 0–511
（Keyboard.KEY_*）；整个会话合计最多 64 个不同键。
单机：什么也不做。
]]
---@param mod table RegisterMod 返回的 Mod 对象
---@param buttons integer[] 键值数组
function CS.Keys(mod, buttons) end

--[[
通知联机层：rate 为 "mark" 的某项声明已经变化，下一个 World 帧读取一次。
只在 Host 上起作用；客机和单机时什么也不做，所以可以直接写在玩法代码里。
target：player 作用域传身体，实体作用域传实体，global 省略。实体作用域省略 target 表示全部实体。
记录还不存在时（会话开始、换局、身体或实体重新出现）联机层会自动读初值，不需要 Mod 标记。
]]
---@param mod table RegisterMod 返回的 Mod 对象
---@param key string 声明名称
---@param target Entity? 目标身体或实体
function CS.MarkDirty(mod, key, target) end

--[[
本端是否是客机。Host 和单机时返回 false。
客机会触发已声明 Mod 的绘制回调；绘制回调里夹带的玩法代码要用它隔开。
]]
---@return boolean
function CS.IsClient()
    return false
end

--[[
返回某个身体所属的参与者序号：0 是房主，1—3 是远端玩家。
一个参与者可以有多个身体（如 Jacob 与 Esau），每个身体都返回同一个序号。
联机时查不到归属返回 nil；单机时本机所有身体（包括本地同屏多人）都返回 0。
]]
---@param player EntityPlayer
---@return integer? 参与者序号
function CS.GetParticipant(player)
    return 0
end

--[[
返回某个参与者的代表身体，不存在时返回 nil。是 GetParticipant 的反查。
单机时只有序号 0 有身体，即 Isaac.GetPlayer(0)。
]]
---@param ordinal integer 参与者序号
---@return EntityPlayer?
function CS.GetPlayerByParticipant(ordinal)
    if ordinal == 0 then return Isaac.GetPlayer(0) end
end

--[[
返回本机参与者的代表身体。客机上 Isaac.GetPlayer(0) 是房主的角色，
"画当前玩家"的 UI 要用这个函数。单机时返回 Isaac.GetPlayer(0)。
]]
---@return EntityPlayer?
function CS.GetLocalPlayer()
    return Isaac.GetPlayer(0)
end

-- 判断某个身体是否由本机控制，用于在多个玩家中挑出本机的那个。单机时总是返回 true。
---@param player EntityPlayer
---@return boolean
function CS.IsLocalPlayer(player)
    return true
end

--[[
注册联机层回调。id 为 IsaacCS.CLIENT_xxx：
  CLIENT_SCENE_STARTED     客机场景开始：第一份状态已装好、首次显示之前。无参数
  CLIENT_SCENE_ENDED       客机场景结束（换层、换局、退出），在 reset 之前。无参数
  CLIENT_ENTITY_INSTALLED  客机实体装好之后（含重建），已能读到同步数据；代替 Init 类回调。参数为实体
  CLIENT_ENTITY_REMOVED    客机实体移除之前，实体还在。参数为实体
  CLIENT_STATE_CHANGED     客机本批状态写完后，对内容有变化的记录派发。参数为声明名称和目标
  CLIENT_INTENT_RESULT     本端发起的意图有了结果（Host、客机、单机都会触发）。
                           参数为意图名称、调用序号、是否成功、结果
单机时只有 CLIENT_INTENT_RESULT 会触发。
]]
---@param mod table RegisterMod 返回的 Mod 对象
---@param id IsaacCSCallback 回调名
---@param fn function 回调函数
function CS.AddCallback(mod, id, fn)
    if not isMod(mod) or type(fn) ~= "function" then return end
    local callbacks = entryOf(mod).callbacks
    local list = callbacks[id] or {}
    list[#list + 1] = fn
    callbacks[id] = list
end

--[[
派发某个 Mod 待交付的意图结果，挂在 MC_POST_RENDER 上。
只派发"产生于更早帧"的结果；本帧产生的（包括在结果回调里又发起的意图）留到下一帧，
保证 SendIntent 的调用方总是先拿到序号、再收到结果。全部派发完后撤下回调。
]]
---@param mod table 回调所属的 Mod
local function deliver(mod)
    local entry = state.entries[mod]
    if not entry or not entry.results then return end
    local now, pending = Isaac.GetFrameCount(), entry.results
    entry.results = {}
    for _, result in ipairs(pending) do
        if result.frame == now then
            entry.results[#entry.results + 1] = result
        else
            for _, callback in ipairs(entry.callbacks.CLIENT_INTENT_RESULT or {}) do
                local ok, err = pcall(callback, result.name, result.seq, result.ok, result.value)
                if not ok then Isaac.DebugString("IsaacCS CLIENT_INTENT_RESULT: " .. tostring(err)) end
            end
        end
    end
    if #entry.results == 0 then
        entry.results = nil
        local callback = entry.deliverCallback
        entry.deliverCallback = nil
        mod:RemoveCallback(ModCallbacks.MC_POST_RENDER, callback)
    end
end

--[[
发起意图，返回调用序号；结果之后通过 CLIENT_INTENT_RESULT 回到本端，按序号对应。
Host、客机、单机三种情况都用同一种写法：
  联机：交给联机层排队，Host 在下一次 Manager::Update 入口执行 handler。
        单个意图内容不超过 512 B，每端在途不超过 8 个、每秒不超过 20 个，超出返回 nil。
  单机：立即以 Isaac.GetPlayer(0) 执行 handler，结果延到下一帧派发。
意图未声明时返回 nil。客机不要提前改已声明的状态，"处理中"放在未声明的变量里。
]]
---@param mod table RegisterMod 返回的 Mod 对象
---@param name string 意图名称
---@param args any 参数，须符合 Intent 声明的 args 类型
---@return integer? 调用序号；失败时为 nil
function CS.SendIntent(mod, name, args)
    local entry = state.entries[mod]
    local handler = entry and entry.intents[name]
    if not handler then return nil end
    state.sequence = state.sequence + 1
    local sequence = state.sequence
    local called, ok, value = pcall(handler, Isaac.GetPlayer(0), args)
    if not called then
        Isaac.DebugString("IsaacCS intent " .. tostring(name) .. ": " .. tostring(ok))
        ok, value = false, nil
    end
    if not entry.results then
        entry.results = {}
        --[[
        REPENTOGON 的 RemoveCallback 只按函数删除、不分 Mod。每个 Mod 登记自己的闭包，
        交付完毕时只撤下本 Mod 的那一条，不连带删掉其他 Mod 仍在等待的交付。
        ]]
        entry.deliverCallback = function(owner) deliver(owner) end
        mod:AddCallback(ModCallbacks.MC_POST_RENDER, entry.deliverCallback)
    end
    entry.results[#entry.results + 1] = { frame = Isaac.GetFrameCount(), name = name, seq = sequence, ok = ok == true, value =
    value }
    return sequence
end

--[[
查询某个玩家是否按住了用 Keys 声明的按键。供 Host 的玩法回调使用。
  联机 Host：返回该身体所属参与者本 tick 的按键状态（远端玩家的按键来自客机上传）；
             未声明的键返回 false。只在模拟 tick 内有效，绘制回调里总是 false。
  客机：总是 false（客机不跑玩法）。
  单机：读本机键盘 Input.IsButtonPressed(key, 0)，不区分 player。
客机 UI 要读本机按键时不用这个函数：在绘制回调里直接用原生 Input.*（键盘查控制器 0）读本机输入，
需要改游戏状态时再用 SendIntent 提交。不要按身体的 ControllerIndex 查询：该值来自 Host，
不一定对应本机设备。
]]
---@param player EntityPlayer
---@param key integer 键值（Keyboard.KEY_*）
---@return boolean
function CS.IsKeyPressed(player, key)
    return Input.IsButtonPressed(key, 0)
end

--[[
查询某个玩家是否在本 tick 刚按下用 Keys 声明的按键（按下的那一刻为 true）。
各情况的行为同 IsKeyPressed，客机上同样总是 false；单机时读 Input.IsButtonTriggered(key, 0)。
客机 UI 读本机按键的做法见 IsKeyPressed 的说明。
]]
---@param player EntityPlayer
---@param key integer 键值（Keyboard.KEY_*）
---@return boolean
function CS.IsKeyTriggered(player, key)
    return Input.IsButtonTriggered(key, 0)
end

if previous and previous.native then
    --[[
    全局是联机层的实现，但它比本 SDK 旧（同版本或更新的已在前面直接返回）。
    不替换它，只把它缺少的函数补成本文件的单机版本，单机照常可玩。
    ]]
    for name, fn in pairs(CS) do
        if existing[name] == nil then existing[name] = fn end
    end
    --[[
    返回给本 Mod 的是一层代理：Declare 至少要求本 SDK 的接口版本，
    联机层不支持时该 Mod 记为"api 版本不受支持"，联机时按未声明处理；其余函数沿用联机层的实现。
    ]]
    ---@param mod table RegisterMod 返回的 Mod 对象
    ---@param info string|{version:string,api:integer?} 同 IsaacCS.Declare
    local function declareNewer(mod, info)
        local release = type(info) == "table" and info.version or info
        local required = type(info) == "table" and info.api or version
        existing.Declare(mod, { version = release, api = math.max(version, required) })
    end
    return setmetatable({ Declare = declareNewer, api = version }, { __index = existing })
end

-- 标记为单机实现（native 为 false）并发布为全局，供之后引入的 SDK 判断能否替换、沿用状态。
CS._isaaccs = { native = false, state = state }
rawset(_G, "IsaacCS", CS)
return CS
