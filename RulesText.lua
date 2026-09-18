--[[
	Edit the text below to change what shows up in the "Rules - read me !"
	window in-game. Keep the [[ ... ]] brackets — that's how Lua marks a
	multi-line block of text. A matching copy is kept in
	Rules_read_me.txt for easy reading/editing outside the game; if you
	change one, copy the change into the other too.
]]

HunterAggroMeterRulesText = [[
Hunter Aggro Meter v.1.23 - Rules

1. This meter estimates threat by comparing your damage to your pet's damage on the current target. It is an approximation, not real threat data.

2. Healing your pet (Mend Pet) also counts as threat: 50% of the healing done is added to your side of the meter.

3. The white line on the bar marks your current aggro threshold. Change it anytime with /ham t <number>, e.g. /ham t 180.

4. Commands:
   /ham show   - show the window
   /ham hide   - hide the window
   /ham lock   - lock/unlock window position
   /ham sound  - toggle sound
   /ham reset  - reset window position
   /ham t <n>  - set aggro threshold %
   /ham doc    - show this window

5. Left-click the "H" button to open/close the meter window. Hold Control and drag it to move it; Control + right-click resets its position.

All tests and settings began on the private-server WOW Classic "Turtle". They continued on the "Raven" server from https://ravencraft.io/
]]
