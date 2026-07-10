----------------------
----GoodTrip1.2.8---
----------------------
HOW TO USE
A)Press Tab + mouseclick on the minimap(the room you want to go) directly.
·Make sure the current room and your target room are clean.
B)For controller or keyboard users, Press MapButton + ↑↓←→ to move the cursor for Selecting target room, in an extra minimap.
·This map can be dragged or pinned with the mouse. When it's pinned, you can click to travel without press TAB.
·If you like, you can change &quot;KeyboardMapEnable = true&quot; to &quot;false&quot; in gtconfig.lua to disable this minimap.(1.2.1 now drag it into the recycle bin just disable it fast)
·If your hudoffset in game is not 0, please change &quot;HudOffset = 0&quot; in gtconfig.lua to match your real hudoffset.
·Set &quot;TeleportAnimation = false&quot; in gtconfig.lua can remove the animation(White flash).(1.2.1:It is now disable by default)
---
tips:
·The location of gtconfig.lua:
*REPENTANCE*
// Windows
...\steam\steamapps\common\Binding of Isaac Rebirth\mods\goodtrip_1630477831\
'General modding changes:
- Mods are now stored in a &quot;mods&quot; folder in the same directory as the rest of the game files
- This directory can be easily accessed by right clicking The Binding of Isaac: Rebirth in the Steam library, then clicking on &quot;Properties&quot;, &quot;Local Files&quot;, and finally &quot;Browse...&quot;'
--
·How to show the built-in cursor:
C:\Users\YourName\My Games\Binding of Isaac Repentance\
edit options.ini
Change MouseControl=0 to MouseControl=1
------------

AB+:
// Windows
C:\Users\YourName\My Games\Binding of Isaac Afterbirth+ Mods\goodtrip_1630477831\
// OSX
~/Library/Application Support/Binding of Isaac Afterbirth+ Mods/goodtrip_1630477831/

·How to show the built-in cursor:
// Windows
C:\Users\YourName\My Games\Binding of Isaac Afterbirth+ \
// OSX
~/Library/Application Support/Binding of Isaac Afterbirth+ /
edit options.ini
Change MouseControl=0 to MouseControl=1



【操作方式】
1.按住地图键(通常是TAB)的同时，鼠标点击右上角小地图的目标房间来进行传送。
·传送需要所在房间和目标房间满足传送条件，基本上要求点亮的房间、地图以及玩家不能处在战斗中。
2.站在原地，按住地图键，用发射眼泪的方向键在「辅助地图」中移动光标选择要去的房间进行传送
·传送条件同上，这个功能是专为手柄和键盘设计的。
·「辅助地图」只有在可以传送的条件下能够呼出，亦可将之用鼠标拖动到任意位置，或点击左上角图钉将之锁定在屏幕上。
·这个地图一样可以用鼠标点击房间来进行传送，而且锁定的情况下不需要按tab直接点击即可。
·如有需要，这个地图可以在配置文件gtconfig.ini中将KeyboardMapEnable = true修改为=false来禁用。

【注意】
·游戏内如果有调整ui偏移量，须用记事本打开同目录下gtconfig.lua设置文件，找到HudOffset = 0 ←修改这个数为游戏菜单设置hud offset数值相同，范围为0~10，来进行校正；或者直接把游戏内ui偏移调整为0，否则会影响选择右上角房间的准确性。
·附加功能 TAB+R 光速重开。 可以在gtconfig文件修改FastRestartEnable开启，为了避免误按默认关闭了。
【附录】
·答gtconfig.lua所在位置
！！忏悔mod在新地址！！
// Windows
...\steam\steamapps\common\Binding of Isaac Rebirth\mods\goodtrip_1630477831\
忏悔改变了mod文件夹，现在在steam里右键游戏访问游戏所在文件夹可以找到同目录下的“mods”文件夹，新的配置文件可能要在这里面更改。
胎衣+
// Windows
C:\Users\YourName\My Games\Binding of Isaac Afterbirth+ Mods\goodtrip_1630477831\
// OSX
~/Library/Application Support/Binding of Isaac Afterbirth+ Mods/goodtrip_1630477831/
·如何开启游戏内置光标（推荐）
// Windows
C:\Users\YourName\My Games\Binding of Isaac Afterbirth+ \
(忏悔的目录是C:\Users\YourName\My Games\Binding of Isaac Repentance\)
// OSX
~/Library/Application Support/Binding of Isaac Afterbirth+ /
编辑 options.ini 文件
把 MouseControl=0 改成 MouseControl=1 并保存


更新日志
2019年1月22日
·看不到地图不能再传送了，这很合理。
·现在不能从未清理的挑战房，br或者小boss房传送出去了。
·现在可以正常传出入刺房了。
·gtconfig中新增了省略传送动画的选项(goodtrip.TeleportAnimation = true修改false即可)
2019年1月28日
·制作了一个新的迷你操作界面来适配键盘和手柄的操作。
·对原有内容进行了大量优化。
2019年1月29日
·修复了传送会触发MAZE二次传送而出现偏差的情况
2019年2月8日
·修复了传送隐藏房意外打开墙壁而免费进入锁房或刺房的bug，并且进行传送时如果必经刺房会被扎。
·修复了仅获得白图也能看到小地图特殊房间的bug。
·现在献祭房和卧室的小地图图标在进入前后的显示正常了。
·新增了一个鼠标拖动窗口时的回收站图标，将辅助窗口拖入回收站可关闭窗口，并且本次游戏内不会再显示。
·修复了和英文EID冲突导致后者不能使用的严重bug。
·现在传送动画是默认关闭的了。
2019年2月9日
·修复了重启mod或重启游戏后继续进行上一局无法正常工作的bug。
2019年3月7日
·现在不会覆盖其他小地图mod的地图样式了，并且gt地图会继承其外观。
·修复了数个与隐藏房传送的相关的问题。
·生命值不符合进入挑战房条件的情况，不可以传送进入挑战房，即使挑战房在地图上是明亮的。
·优化了键盘操作模式的运算量。(鼠标模式本身运算量极小)
2021年5月18日
·响应忏悔更新，先修复了一些严重bug，mod系统更加完善后还会持续更新。
2021年5月21日
·修复了用卡牌传入未发现的隐藏房会使手柄控制传送暂时失效的问题。
·现在拿着饰品锉刀和心脏等道具传送刺房不会受伤了。
·小地图红房间现在是红色了。
·修复了天使房、恶魔房、红宝房、贪婪出口等房间图标显示不正常的问题。
·修改了挑战房传限制，暂时移除了提示音。
2021年5月22日
·修复了之前隐藏房相关修复后出现的“boss房无法传送”问题。
2021年6月1日
·修复了追逐战可以跳过的bug。
·修复了几个因为版本更新而异常的功能（诅咒、刺房伤害延迟、挑战房等），并进行了优化。
2021年6月6日
·优化了同时涉及隐藏房和刺房的逻辑让传送工作地更自然。
--- 已知的未修复bug：
·大多数情况下，两个房间只要满足普适传送条件，即使并没有路径相连，也可以进行传送。
·镜像层右上角地图也是镜像的，点选会不准确，现在暂时还不知道怎么判断自己身处镜子之中。
·初始房间使用后悔药返回上一层后 快捷地图的房间有些会显示成红房间。
·其他的一些导致不能传送的bug，希望能留言告诉我。
※为避免更新太频繁，良性bug将会经过修复，一定时间测试无误后再一并更新。请大家留意任何bug并向我反馈！

2026年7月4日（良好旅行[Fixed]，适配忏悔+）
·适配忏悔+，修复了TAB+R光速重开失效的问题。
·修复了鼠标悬停在小地图上时方向键无法呼出光标的问题（现在以最后操作的设备为准）。
·修复了切换房间后键盘光标残留、导致光标消失的问题。
·修复了镜像层右上角大地图点选偏移的问题（现在已能判断身处镜中，对应上方已知bug）。
·修复了镜像层键盘光标会移出地图边界的问题。
·修复了从隐藏房传送时偶发的崩溃。
·修复了锁定小地图后在镜像层点选会传送到镜像房间的问题。
·修复了中途修改HUD偏移后大地图点选错位的问题。
·新增：镜内世界（镜像层）的宝箱房与商店现在也视为免费、可直接传送到达。

2026年7月9日
·公平计时（FairTripTime）的寻路算法重写为广度优先最短路（原实现枚举全部路径，最坏情况指数级，属防患加固），并修复了 MinimapAPI 查不到房间时可能的崩溃。
·新增MinimapAPI联动总开关（MCM: MinimapAPICompat），默认关闭；公平计时需要开启该选项才生效。

2026年7月10日
·新增小地图缩放：MCM 滑条（x0.5~x2.5）+ 地图上的缩放按钮（循环 x1.0/x1.5/x2.0，图钉锁定时也能点，无需 MCM）。
·小地图窗口现在保持最小 3×3 并居中显示房间，开局只发现一间房时按钮也放得下。
·修复了点击地图边缘像素可能选中相邻行房间的隐藏 bug。
·描述中的 Mod Config Menu 链接更换为原作者官方续作 Impure（旧版 Pure 已被工坊下架）。
·修复了原版遗留的邻接回绕 bug：地图最左缘的房间会把相邻行最右缘的房间误判为"已清邻居"而放行本不该允许的传送（公平计时的最后一跳判定同样受益）。