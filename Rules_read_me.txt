Hunter Aggro Meter - Rules

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

NOTE: This file is not read by the game directly (WoW addons cannot read
arbitrary files from disk). The in-game window shows the copy of this
text stored in RulesText.lua. If you edit this .txt file, copy the same
change into RulesText.lua so the in-game window matches.

ps
All tests and settings began on the private-server WOW Classic “Turtle”. They continued on the "Raven" server from https://ravencraft.io/
