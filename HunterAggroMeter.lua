--[[
	Hunter Aggro Meter (Solo)
	-------------------------
	Аддон для WoW Classic / vanilla-совместимых серверов.

	Хантер соло фармит, пет танчит моба. Окно показывает ОДНУ большую
	полосу — твой агро относительно пета (0% = чисто, 100% = сравнялся
	с петом = вот-вот перетянешь), с меткой-порогом на 100%, плюс
	маленькую полосу пета и текст "кто держит агро сейчас".

	Два режима работы, выбирается автоматически:
	  1) ТОЧНЫЙ — если на сервере есть UnitDetailedThreatSituation
	     (появилась в официальном патче 1.13.5), берём угрозу прямо
	     из игры.
	  2) ПРИБЛИЗИТЕЛЬНЫЙ — если этой функции нет (чистый vanilla-API),
	     считаем через combat log: сравниваем урон игрока и урон пета
	     по текущей цели. Это не настоящая угроза, а прикидка на
	     глаз, но на практике неплохо коррелирует.

	Написан максимально совместимо со старым (1.12-подобным) Lua/UI
	API: без SetSize (только SetWidth/SetHeight), без SetColorTexture
	(только SetTexture с цветовыми аргументами), без BackdropTemplate,
	обработчики скриптов не полагаются на параметр self/event/elapsed
	(на некоторых серверах они не передаются, используется глобальный
	`this`/`event`/`argN`).

	Команды:
		/ham lock      - закрепить/открепить перемещение окна
		/ham sound     - вкл/выкл звуковое предупреждение
		/ham reset     - сбросить позицию окна
]]

local ADDON_NAME = "HunterAggroMeter"

HunterAggroMeterDB = HunterAggroMeterDB or {
	point = "CENTER",
	relPoint = "CENTER",
	x = 0,
	y = -150,
	locked = false,
	sound = true,
	threshold = nil, -- nil = use default (100 precise mode / 130 approx mode)
	hidden = false,
	btnPoint = "CENTER",
	btnRelPoint = "CENTER",
	btnX = 0,
	btnY = 120,
	btnLayoutVersion = 3,
}

-- Если у игрока сохранена позиция кнопки от старой версии аддона
-- (нижний правый угол, где её не было видно) — переносим на новую
-- позицию (верх экрана, под миникартой).
if HunterAggroMeterDB.btnLayoutVersion ~= 3 then
	HunterAggroMeterDB.btnPoint = "CENTER"
	HunterAggroMeterDB.btnRelPoint = "CENTER"
	HunterAggroMeterDB.btnX = 0
	HunterAggroMeterDB.btnY = 120
	HunterAggroMeterDB.btnLayoutVersion = 3
end

local BAR_WIDTH = 206

-- Точный режим (реальная угроза): 100% = сравнялся с текущим "танком",
-- это уже готовое значение от игры.
-- Приблизительный режим (по урону): у дальних атак (автовыстрел
-- хантера — почти весь его урон) в WoW действует правило "запаса" —
-- чтобы реально перетянуть агро, нужно превысить угрозу танка примерно
-- на 30%, а не просто сравняться. Поэтому порог здесь выше.
-- Порог можно менять вручную командой /ham t <число> — значение
-- сохраняется и подставляется по умолчанию при следующей загрузке.
local hasThreatAPI = (type(UnitDetailedThreatSituation) == "function")
local DEFAULT_THRESHOLD = hasThreatAPI and 100 or 130
local AGGRO_THRESHOLD = HunterAggroMeterDB.threshold or DEFAULT_THRESHOLD

local function GetBarCap()
	return math.max(130, AGGRO_THRESHOLD * 1.2)
end

----------------------------------------------------------------
-- Frame
----------------------------------------------------------------

local frame = CreateFrame("Frame", "HunterAggroMeterFrame", UIParent)
frame:SetWidth(230); frame:SetHeight(102)
frame:SetPoint(HunterAggroMeterDB.point, UIParent, HunterAggroMeterDB.relPoint, HunterAggroMeterDB.x, HunterAggroMeterDB.y)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
if frame.SetClampedToScreen then
	frame:SetClampedToScreen(true)
end

local mainBG = frame:CreateTexture(nil, "BACKGROUND")
mainBG:SetAllPoints(frame)
mainBG:SetTexture(0, 0, 0, 0.55)

-- Крестик закрытия окна в правом верхнем углу — та же надёжная
-- техника (сплошные цветные текстуры), что и у кнопки "H", вместо
-- путей к стандартным текстурам Blizzard, которые могут не
-- прогрузиться на этом клиенте.
local closeBtn = CreateFrame("Button", nil, frame)
closeBtn:SetWidth(18); closeBtn:SetHeight(18)
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)

local closeBtnBorder = closeBtn:CreateTexture(nil, "BACKGROUND")
closeBtnBorder:SetPoint("TOPLEFT", closeBtn, "TOPLEFT", -2, 2)
closeBtnBorder:SetPoint("BOTTOMRIGHT", closeBtn, "BOTTOMRIGHT", 2, -2)
closeBtnBorder:SetTexture(1, 0.82, 0, 0.9)

local closeBtnBG = closeBtn:CreateTexture(nil, "BACKGROUND")
closeBtnBG:SetAllPoints(closeBtn)
closeBtnBG:SetTexture(0.15, 0.15, 0.15, 0.95)

local closeBtnLabel = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
closeBtnLabel:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
closeBtnLabel:SetText("X")
closeBtnLabel:SetTextColor(1, 0.2, 0.2)

local closeBtnHighlight = closeBtn:CreateTexture(nil, "HIGHLIGHT")
closeBtnHighlight:SetAllPoints(closeBtn)
closeBtnHighlight:SetTexture(1, 1, 1, 0.3)

closeBtn:SetScript("OnClick", function()
	frame:Hide()
end)

if HunterAggroMeterDB.hidden then
	frame:Hide()
end
frame:SetScript("OnHide", function()
	HunterAggroMeterDB.hidden = true
end)
frame:SetScript("OnShow", function()
	HunterAggroMeterDB.hidden = false
end)

-- Перетаскивание: НЕ полагаемся на параметр self, используем upvalue
-- frame напрямую — работает и на старом (this-based), и на новом API.
frame:SetScript("OnDragStart", function()
	if not HunterAggroMeterDB.locked then
		frame:StartMoving()
	end
end)
frame:SetScript("OnDragStop", function()
	frame:StopMovingOrSizing()
	local point, _, relPoint, x, y = frame:GetPoint()
	HunterAggroMeterDB.point = point
	HunterAggroMeterDB.relPoint = relPoint
	HunterAggroMeterDB.x = x
	HunterAggroMeterDB.y = y
end)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOP", frame, "TOP", 0, -4)
title:SetText("Your aggro vs pet")

----------------------------------------------------------------
-- Главная полоса
----------------------------------------------------------------

local playerBar = CreateFrame("StatusBar", nil, frame)
playerBar:SetWidth(BAR_WIDTH); playerBar:SetHeight(26)
playerBar:SetPoint("TOP", title, "BOTTOM", 0, -15)
playerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
playerBar:SetMinMaxValues(0, GetBarCap())
playerBar:SetValue(0)
playerBar:SetStatusBarColor(0.1, 0.8, 0.1)

local playerBarBG = playerBar:CreateTexture(nil, "BACKGROUND")
playerBarBG:SetAllPoints(playerBar)
playerBarBG:SetTexture(0, 0, 0, 0.45)

local thresholdLine = playerBar:CreateTexture(nil, "OVERLAY")
thresholdLine:SetTexture(1, 1, 1, 0.9)
thresholdLine:SetWidth(2); thresholdLine:SetHeight(26)

local thresholdLabel = playerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
thresholdLabel:SetText(AGGRO_THRESHOLD .. "%")

local playerText = playerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
playerText:SetPoint("CENTER", playerBar, "CENTER", 0, 0)
playerText:SetText("--")

local function PositionThresholdLine()
	local _, maxV = playerBar:GetMinMaxValues()
	local frac = AGGRO_THRESHOLD / maxV
	if frac > 1 then frac = 1 end
	thresholdLine:ClearAllPoints()
	thresholdLine:SetPoint("TOP", playerBar, "TOPLEFT", BAR_WIDTH * frac, 0)
	thresholdLabel:ClearAllPoints()
	thresholdLabel:SetPoint("BOTTOM", thresholdLine, "TOP", 0, 2)
end
PositionThresholdLine()

----------------------------------------------------------------
-- Маленькая полоса пета
----------------------------------------------------------------

local petBar = CreateFrame("StatusBar", nil, frame)
petBar:SetWidth(BAR_WIDTH); petBar:SetHeight(10)
petBar:SetPoint("TOP", playerBar, "BOTTOM", 0, -12)
petBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
petBar:SetMinMaxValues(0, 100)
petBar:SetValue(0)
petBar:SetStatusBarColor(0.2, 0.5, 0.9)

local petBarBG = petBar:CreateTexture(nil, "BACKGROUND")
petBarBG:SetAllPoints(petBar)
petBarBG:SetTexture(0, 0, 0, 0.4)

local petLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
petLabel:SetPoint("BOTTOMLEFT", petBar, "TOPLEFT", 0, 2)
petLabel:SetText("Pet damage (reference)")

local petText = petBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
petText:SetPoint("CENTER", petBar, "CENTER", 0, 0)
petText:SetText("--")

----------------------------------------------------------------
-- Статусная строка
----------------------------------------------------------------

local statusLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
statusLine:SetPoint("TOP", petBar, "BOTTOM", 0, -5)
statusLine:SetText("Tank: --")

----------------------------------------------------------------
-- Постоянная кнопка-переключатель (видна всегда, даже если окно
-- аддона закрыто крестиком). ЛКМ - открыть/закрыть окно. Ctrl+drag -
-- подвинуть саму кнопку. Ctrl+ПКМ - сбросить позицию кнопки.
----------------------------------------------------------------

local launcher = CreateFrame("Button", "HunterAggroMeterLauncher", UIParent)
launcher:SetWidth(30); launcher:SetHeight(30)
launcher:SetPoint(HunterAggroMeterDB.btnPoint, UIParent, HunterAggroMeterDB.btnRelPoint, HunterAggroMeterDB.btnX, HunterAggroMeterDB.btnY)
launcher:SetFrameStrata("HIGH")
launcher:SetMovable(true)
if launcher.SetToplevel then
	launcher:SetToplevel(true)
end
launcher:EnableMouse(true)
launcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
launcher:RegisterForDrag("LeftButton")
if launcher.SetClampedToScreen then
	launcher:SetClampedToScreen(true)
end

-- Тёмный квадрат-подложка — простая цветная текстура, гарантированно
-- видна на любом клиенте (уже проверено на фоне главного окна).
local launcherBG = launcher:CreateTexture(nil, "BACKGROUND")
launcherBG:SetPoint("TOPLEFT", launcher, "TOPLEFT", 4, -4)
launcherBG:SetPoint("BOTTOMRIGHT", launcher, "BOTTOMRIGHT", -4, 4)
launcherBG:SetTexture(0.1, 0.1, 0.1, 0.9)

local launcherLabel = launcher:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
launcherLabel:SetPoint("CENTER", launcher, "CENTER", 0, 0)
launcherLabel:SetText("H")

-- Круглая золотая рамка "под миникарту", как у кнопок на миникарте.
-- Если по какой-то причине текстура не подгрузится — квадрат-подложка
-- с буквой "H" всё равно останется видимым и рабочим.
local launcherRing = launcher:CreateTexture(nil, "OVERLAY")
launcherRing:SetAllPoints(launcher)
launcherRing:SetTexture("Interface\\Minimap\\MinimapButtonBorder")

local launcherHighlight = launcher:CreateTexture(nil, "HIGHLIGHT")
launcherHighlight:SetPoint("TOPLEFT", launcher, "TOPLEFT", 4, -4)
launcherHighlight:SetPoint("BOTTOMRIGHT", launcher, "BOTTOMRIGHT", -4, 4)
launcherHighlight:SetTexture(1, 1, 1, 0.3)

launcher:Show()

local function ToggleMainWindow()
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
	end
end

local function ResetLauncherPosition()
	HunterAggroMeterDB.btnPoint = "CENTER"
	HunterAggroMeterDB.btnRelPoint = "CENTER"
	HunterAggroMeterDB.btnX = 0
	HunterAggroMeterDB.btnY = 120
	launcher:ClearAllPoints()
	launcher:SetPoint(HunterAggroMeterDB.btnPoint, UIParent, HunterAggroMeterDB.btnRelPoint, HunterAggroMeterDB.btnX, HunterAggroMeterDB.btnY)
end

launcher:SetScript("OnClick", function(selfArg, mouseButton)
	local btn = mouseButton or arg1
	if btn == "RightButton" then
		if IsControlKeyDown() then
			ResetLauncherPosition()
		end
	else
		ToggleMainWindow()
	end
end)

launcher:SetScript("OnDragStart", function()
	if IsControlKeyDown() then
		launcher:StartMoving()
	end
end)
launcher:SetScript("OnDragStop", function()
	launcher:StopMovingOrSizing()
	local point, _, relPoint, x, y = launcher:GetPoint()
	HunterAggroMeterDB.btnPoint = point
	HunterAggroMeterDB.btnRelPoint = relPoint
	HunterAggroMeterDB.btnX = x
	HunterAggroMeterDB.btnY = y
end)

launcher:SetScript("OnEnter", function()
	GameTooltip:SetOwner(launcher, "ANCHOR_LEFT")
	GameTooltip:AddLine("Hunter Aggro Meter")
	GameTooltip:AddLine("Left-click to open/close the window.", 1, 0.82, 0)
	GameTooltip:AddLine("Hold control and drag to move.", 1, 0.82, 0)
	GameTooltip:AddLine("Hold control and right-click to reset position.", 1, 0.82, 0)
	GameTooltip:AddLine("Type /ham doc to show Rules - read me !", 1, 0.82, 0)
	GameTooltip:Show()
end)
launcher:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

----------------------------------------------------------------
-- Окно "Rules - read me !" — центрируется на экране при каждом
-- открытии, текст берётся из RulesText.lua (14pt шрифт), со
-- скроллом, так как текст обычно не помещается целиком.
----------------------------------------------------------------

local rulesFrame = CreateFrame("Frame", "HunterAggroMeterRulesFrame", UIParent)
rulesFrame:SetWidth(420); rulesFrame:SetHeight(320)
rulesFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
rulesFrame:SetFrameStrata("DIALOG")
rulesFrame:EnableMouse(true)
rulesFrame:Hide()

local rulesBG = rulesFrame:CreateTexture(nil, "BACKGROUND")
rulesBG:SetAllPoints(rulesFrame)
rulesBG:SetTexture(0, 0, 0, 0.85)

-- Крестик закрытия — тот же надёжный стиль, что и у главного окна.
local rulesCloseBtn = CreateFrame("Button", nil, rulesFrame)
rulesCloseBtn:SetWidth(18); rulesCloseBtn:SetHeight(18)
rulesCloseBtn:SetPoint("TOPRIGHT", rulesFrame, "TOPRIGHT", -3, -3)

local rulesCloseBorder = rulesCloseBtn:CreateTexture(nil, "BACKGROUND")
rulesCloseBorder:SetPoint("TOPLEFT", rulesCloseBtn, "TOPLEFT", -2, 2)
rulesCloseBorder:SetPoint("BOTTOMRIGHT", rulesCloseBtn, "BOTTOMRIGHT", 2, -2)
rulesCloseBorder:SetTexture(1, 0.82, 0, 0.9)

local rulesCloseBG = rulesCloseBtn:CreateTexture(nil, "BACKGROUND")
rulesCloseBG:SetAllPoints(rulesCloseBtn)
rulesCloseBG:SetTexture(0.15, 0.15, 0.15, 0.95)

local rulesCloseLabel = rulesCloseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rulesCloseLabel:SetPoint("CENTER", rulesCloseBtn, "CENTER", 0, 0)
rulesCloseLabel:SetText("X")
rulesCloseLabel:SetTextColor(1, 0.2, 0.2)

local rulesCloseHighlight = rulesCloseBtn:CreateTexture(nil, "HIGHLIGHT")
rulesCloseHighlight:SetAllPoints(rulesCloseBtn)
rulesCloseHighlight:SetTexture(1, 1, 1, 0.3)

rulesCloseBtn:SetScript("OnClick", function()
	rulesFrame:Hide()
end)

local rulesHeader = rulesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
rulesHeader:SetPoint("TOP", rulesFrame, "TOP", 0, -12)
rulesHeader:SetText("Rules - read me !")

-- Область прокрутки: ScrollFrame + внутренний Frame-контейнер с
-- текстом, плюс собственный вертикальный Slider как полоса прокрутки
-- (без XML-шаблонов, которые ненадёжны на этом клиенте).
local SCROLL_WIDTH = 360

local rulesScroll = CreateFrame("ScrollFrame", nil, rulesFrame)
rulesScroll:SetPoint("TOPLEFT", rulesFrame, "TOPLEFT", 16, -40)
rulesScroll:SetPoint("BOTTOMRIGHT", rulesFrame, "BOTTOMRIGHT", -36, 12)
rulesScroll:EnableMouseWheel(true)

local rulesScrollChild = CreateFrame("Frame", nil, rulesScroll)
rulesScrollChild:SetWidth(SCROLL_WIDTH); rulesScrollChild:SetHeight(1)
rulesScroll:SetScrollChild(rulesScrollChild)

local rulesBody = rulesScrollChild:CreateFontString(nil, "OVERLAY")
if rulesBody.SetFont then
	rulesBody:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
end
rulesBody:SetPoint("TOPLEFT", rulesScrollChild, "TOPLEFT", 0, 0)
rulesBody:SetWidth(SCROLL_WIDTH)
rulesBody:SetJustifyH("LEFT")
rulesBody:SetJustifyV("TOP")
rulesBody:SetText(HunterAggroMeterRulesText or "Rules_read_me.txt content goes here.")
rulesScrollChild:SetHeight(rulesBody:GetHeight() + 4)

local rulesScrollBar = CreateFrame("Slider", nil, rulesFrame)
rulesScrollBar:SetWidth(16)
rulesScrollBar:SetPoint("TOPRIGHT", rulesFrame, "TOPRIGHT", -10, -40)
rulesScrollBar:SetPoint("BOTTOMRIGHT", rulesFrame, "BOTTOMRIGHT", -10, 12)
if rulesScrollBar.SetOrientation then
	rulesScrollBar:SetOrientation("VERTICAL")
end
rulesScrollBar:SetValueStep(1)
rulesScrollBar:SetValue(0)

local rulesScrollTrack = rulesScrollBar:CreateTexture(nil, "BACKGROUND")
rulesScrollTrack:SetAllPoints(rulesScrollBar)
rulesScrollTrack:SetTexture(0.1, 0.1, 0.1, 0.9)

local rulesScrollThumb = rulesScrollBar:CreateTexture(nil, "OVERLAY")
rulesScrollThumb:SetWidth(16); rulesScrollThumb:SetHeight(28)
rulesScrollThumb:SetTexture(1, 0.82, 0, 0.9)
if rulesScrollBar.SetThumbTexture then
	rulesScrollBar:SetThumbTexture(rulesScrollThumb)
end

local function UpdateRulesScrollRange()
	local visibleHeight = rulesScroll:GetHeight() or 0
	local contentHeight = rulesScrollChild:GetHeight() or 0
	local maxScroll = contentHeight - visibleHeight
	if maxScroll < 0 then maxScroll = 0 end
	rulesScrollBar:SetMinMaxValues(0, maxScroll)
end

rulesScrollBar:SetScript("OnValueChanged", function(selfArg, value)
	local v = value or arg1 or 0
	rulesScroll:SetVerticalScroll(v)
end)

rulesScroll:SetScript("OnMouseWheel", function(selfArg, delta)
	local d = delta or arg1 or 0
	local cur = rulesScrollBar:GetValue()
	local minV, maxV = rulesScrollBar:GetMinMaxValues()
	local newVal = cur - (d * 20)
	if newVal < minV then newVal = minV end
	if newVal > maxV then newVal = maxV end
	rulesScrollBar:SetValue(newVal)
end)

local function ShowRulesWindow()
	rulesFrame:ClearAllPoints()
	rulesFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	UpdateRulesScrollRange()
	rulesFrame:Show()
end

----------------------------------------------------------------
-- Режим работы
----------------------------------------------------------------

if hasThreatAPI then
	title:SetText("Your aggro vs pet")
else
	title:SetText("Your damage vs pet (approx)")
	petLabel:SetText("Pet damage (reference)")
	print("|cffffcc00Hunter Aggro Meter|r: no real threat API on this server, estimating via damage (combat log).")
end

print("|cff33ff99Hunter Aggro Meter|r: aggro threshold is currently " .. AGGRO_THRESHOLD .. "%. Change it with /ham t <number>, e.g. /ham t 180.")

----------------------------------------------------------------
-- Общая логика полос/цвета/звука
----------------------------------------------------------------

local lastAlertState = -1

local function ColorForRaw(raw)
	if raw == nil then
		return 0.5, 0.5, 0.5
	elseif raw < AGGRO_THRESHOLD * 0.6 then
		return 0.1, 0.8, 0.1
	elseif raw < AGGRO_THRESHOLD * 0.9 then
		return 0.9, 0.9, 0.1
	elseif raw < AGGRO_THRESHOLD then
		return 1, 0.6, 0
	else
		return 1, 0.1, 0.1
	end
end

local function PlayAlert(state)
	if not HunterAggroMeterDB.sound then return end
	if state == lastAlertState then return end
	if state >= 1 and lastAlertState < state then
		PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
	end
	lastAlertState = state
end

local function ResetMeter()
	playerBar:SetMinMaxValues(0, GetBarCap())
	playerBar:SetValue(0)
	PositionThresholdLine()
	playerText:SetText("--")
	petBar:SetValue(0)
	petText:SetText("--")
	statusLine:SetText("Tank: --")
	statusLine:SetTextColor(1, 1, 1)
	lastAlertState = -1
end

local function RenderMeter(value, isTankingPlayer, hasPet, isTankingPet, petDisplayValue, noData)
	local cap = GetBarCap()
	if value > cap then
		cap = value + 15
	end
	playerBar:SetMinMaxValues(0, cap)
	playerBar:SetValue(value)
	PositionThresholdLine()

	local r, g, b = ColorForRaw(value)
	playerBar:SetStatusBarColor(r, g, b)

	if noData then
		playerText:SetText("no data")
	else
		playerText:SetText(string.format("%d%%", math.floor(value)))
	end

	if hasPet then
		petBar:Show()
		petLabel:Show()
		petBar:SetValue(petDisplayValue or 0)
		petText:SetText(petDisplayValue and string.format("%d%%", math.floor(petDisplayValue)) or "--")
	else
		petBar:Hide()
		petLabel:Hide()
	end

	local alertState = 0
	if isTankingPlayer then
		statusLine:SetText("Tank: YOU! Aggro on you!")
		statusLine:SetTextColor(1, 0.15, 0.15)
		alertState = 2
	elseif hasPet and (isTankingPet or not hasThreatAPI) then
		if value >= AGGRO_THRESHOLD * 0.9 then
			statusLine:SetText("Tank: pet (close to pulling)")
			statusLine:SetTextColor(1, 0.6, 0)
			alertState = 1
		else
			statusLine:SetText("Tank: pet")
			statusLine:SetTextColor(0.4, 0.9, 1)
			alertState = 0
		end
	elseif not hasPet then
		statusLine:SetText("Tank: no pet!")
		statusLine:SetTextColor(1, 0.6, 0)
	else
		statusLine:SetText("Tank: unknown")
		statusLine:SetTextColor(1, 1, 1)
	end

	PlayAlert(alertState)
end

----------------------------------------------------------------
-- РЕЖИМ 1: точный, через UnitDetailedThreatSituation
----------------------------------------------------------------

local function UpdatePreciseMeter()
	if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target") then
		ResetMeter()
		return
	end

	local isTankingP, statusP, _, rawP = UnitDetailedThreatSituation("player", "target")
	local hasPet = UnitExists("pet")
	local isTankingPet, statusPet, scaledPet
	if hasPet then
		isTankingPet, statusPet, scaledPet = UnitDetailedThreatSituation("pet", "target")
	end

	local value = rawP or 0
	if isTankingP then
		value = math.max(value, AGGRO_THRESHOLD)
	end

	RenderMeter(value, isTankingP, hasPet, isTankingPet, scaledPet, statusP == nil)
end

----------------------------------------------------------------
-- РЕЖИМ 2: приблизительный, через СТАРЫЙ combat log (текстовые
-- события CHAT_MSG_COMBAT_*, единственное что реально есть на
-- чистой ванилле 1.12 — COMBAT_LOG_EVENT_UNFILTERED там не существует)
----------------------------------------------------------------

local playerDamage, petDamage = 0, 0
local trackedTargetName = nil
local lastComputedValue = 0

local function ResetDamageTracking()
	playerDamage, petDamage = 0, 0
	trackedTargetName = UnitExists("target") and UnitName("target") or nil
end

----------------------------------------------------------------
-- Feign Death: сброс агро с восстановлением по таймеру
----------------------------------------------------------------

local fdActive = false
local fdRemember = 0
local fdTimeLeft = 0
local fdSecondAccum = 0
local fdWasActive = false

-- Плавающий таймер обратного отсчёта. Настоящего API "текст у ног
-- персонажа в 3D-мире" в этом клиенте нет, поэтому это экранная
-- метка, зафиксированная чуть ниже центра экрана — там, где обычно
-- находится персонаж в стандартной камере от третьего лица.
local fdCountdownFrame = CreateFrame("Frame", nil, UIParent)
fdCountdownFrame:SetWidth(140); fdCountdownFrame:SetHeight(40)
fdCountdownFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
fdCountdownFrame:SetFrameStrata("HIGH")
fdCountdownFrame:Hide()

local fdCountdownText = fdCountdownFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
fdCountdownText:SetPoint("CENTER", fdCountdownFrame, "CENTER", 0, 0)
if fdCountdownText.SetFont then
	fdCountdownText:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE")
end
fdCountdownText:SetTextColor(1, 0.9, 0.2)
fdCountdownText:SetText("10")

local function IsFeignDeathActive()
	local i = 1
	while true do
		local name = UnitBuff("player", i)
		if not name then break end
		if name == "Feign Death" then
			return true
		end
		i = i + 1
	end
	return false
end

local function StopFeignDeath()
	fdActive = false
	fdCountdownFrame:Hide()
end

local function StartFeignDeath()
	fdRemember = lastComputedValue
	fdActive = true
	fdTimeLeft = 10
	fdSecondAccum = 0
	fdCountdownText:SetText(tostring(fdTimeLeft))
	fdCountdownFrame:Show()
end

-- Вызывается при любом первом действии игрока (выстрел/каст/хил
-- пета) во время активного FD-таймера. rawAmount — величина этого
-- конкретного действия в тех же единицах, что и playerDamage/petDamage
-- (для хила это уже amount*0.5, коэффициент угрозы от хила).
local function ResolveFeignDeathAction(rawAmount)
	if not fdActive then return end

	local fraction
	if fdTimeLeft > 5 then
		fraction = 1 / 3
	else
		fraction = 1 / 10
	end

	local hitPercent
	if petDamage > 0 then
		hitPercent = (rawAmount / petDamage) * 100
	else
		hitPercent = rawAmount
	end

	local restored = (fdRemember * fraction) + hitPercent
	if restored < 0 then restored = 0 end

	-- "Досеиваем" playerDamage так, чтобы обычная формула (playerDamage
	-- / petDamage * 100) дальше сама естественно давала restored%.
	if petDamage > 0 then
		playerDamage = (restored / 100) * petDamage
	else
		playerDamage = restored
	end

	StopFeignDeath()
end

-- Дёргается из общего OnUpdate (не троттлится, нужен точный тик раз в
-- секунду для отсчёта).
local function CheckFeignDeathState(dt)
	local isFD = IsFeignDeathActive()
	if isFD and not fdWasActive then
		StartFeignDeath()
	end
	fdWasActive = isFD

	if fdActive then
		fdSecondAccum = fdSecondAccum + dt
		if fdSecondAccum >= 1 then
			fdSecondAccum = fdSecondAccum - 1
			fdTimeLeft = fdTimeLeft - 1
			if fdTimeLeft < 0 then fdTimeLeft = 0 end
			fdCountdownText:SetText(tostring(fdTimeLeft))
		end
	end
end

-- Достаём число урона из текста лога, не завязываясь на точную
-- формулировку (hit/crit/hits/critically hits и т.п.) — ищем "for N"
-- перед словом damage или перед концом фразы/точкой.
local function ExtractDamageAmount(msg)
	if not msg then return nil end
	local _, _, amount = string.find(msg, "for (%d+)%s+damage")
	if not amount then _, _, amount = string.find(msg, "for (%d+)%s*%.") end
	if not amount then _, _, amount = string.find(msg, "for (%d+)$") end
	if not amount then _, _, amount = string.find(msg, "for (%d+)") end
	return amount and tonumber(amount) or nil
end

-- source: "player" или "pet" — определяется тем, из какого именно
-- события пришло сообщение (см. регистрацию событий ниже), а не
-- парсингом текста, это надёжнее.
local function HandleCombatChatMsg(source, msg)
	if not trackedTargetName or not msg then return end
	if not string.find(msg, trackedTargetName, 1, true) then return end

	local amount = ExtractDamageAmount(msg)
	if not amount then return end

	if source == "player" then
		if fdActive then
			ResolveFeignDeathAction(amount)
		else
			playerDamage = playerDamage + amount
		end
	elseif source == "pet" then
		petDamage = petDamage + amount
	end
end

-- Достаём число хила из текста лога (Mend Pet и подобные): формат
-- обычно "PetName gains N health from Mend Pet." — ищем "gains N health".
local function ExtractHealAmount(msg)
	if not msg then return nil end
	local _, _, amount = string.find(msg, "gains (%d+) health")
	if not amount then _, _, amount = string.find(msg, "healed for (%d+)") end
	if not amount then _, _, amount = string.find(msg, "for (%d+) health") end
	if not amount then _, _, amount = string.find(msg, "for (%d+)") end
	return amount and tonumber(amount) or nil
end

-- Хил пета тоже создаёт угрозу — считаем 50% от объёма хила как
-- "урон" в общем зачёте игрока, иначе можно случайно переагрить
-- моба чистым хилом, не нанося урона вообще.
local function HandleHealChatMsg(msg)
	if not trackedTargetName or not msg then return end
	local petName = UnitExists("pet") and UnitName("pet") or nil
	if not petName then return end
	if not string.find(msg, petName, 1, true) then return end

	local amount = ExtractHealAmount(msg)
	if not amount then return end

	local threatEquivalent = amount * 0.5
	if fdActive then
		ResolveFeignDeathAction(threatEquivalent)
	else
		playerDamage = playerDamage + threatEquivalent
	end
end

local function UpdateApproxMeter()
	if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target") then
		ResetMeter()
		trackedTargetName = nil
		StopFeignDeath()
		return
	end

	local curName = UnitName("target")
	if curName ~= trackedTargetName then
		ResetDamageTracking()
		StopFeignDeath()
	end

	local hasPet = UnitExists("pet")
	local noData = (playerDamage == 0 and petDamage == 0)

	-- value: наш урон в % от урона пета (100% = сравнялись). Пока
	-- активен Feign Death - полоса игрока принудительно на нуле,
	-- независимо от того, что происходит с петом.
	local value
	if fdActive then
		value = 0
	else
		if petDamage <= 0 then
			value = playerDamage > 0 and 100 or 0
		else
			value = (playerDamage / petDamage) * 100
		end
		lastComputedValue = value
	end

	-- petDisplayValue: просто показываем 100 фикс (шкала пета тут не
	-- несёт отдельного смысла, используем как "живую" полосу активности)
	local petDisplayValue = hasPet and math.min(100, (petDamage > 0 and 100 or 0)) or 0

	-- В приблизительном режиме мы не можем достоверно знать, что
	-- агро РЕАЛЬНО сорвалось — только что твой урон обогнал урон
	-- пета, поэтому "isTankingPlayer" тут всегда false.
	RenderMeter(value, false, hasPet, true, petDisplayValue, noData)
end

----------------------------------------------------------------
-- События
----------------------------------------------------------------

-- Какое событие какому источнику урона соответствует (старый стиль,
-- реально существующий на ванилле 1.12).
local COMBAT_CHAT_EVENTS = {
	CHAT_MSG_COMBAT_SELF_HITS = "player",
	CHAT_MSG_SPELL_SELF_DAMAGE = "player",
	CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE = "player",
	CHAT_MSG_COMBAT_PET_HITS = "pet",
	CHAT_MSG_SPELL_PET_DAMAGE = "pet",
}

-- Точное название события для хила пета (Mend Pet) на этом клиенте
-- достоверно неизвестно (в открытых источниках не задокументировано),
-- поэтому регистрируем сразу несколько вероятных вариантов по аналогии
-- с уже подтверждёнными именами событий урона — лишняя регистрация
-- несуществующего имени события безвредна, просто никогда не сработает.
local HEAL_CHAT_EVENTS = {
	"CHAT_MSG_SPELL_SELF_HEAL",
	"CHAT_MSG_SPELL_PERIODIC_SELF_HEAL",
	"CHAT_MSG_SPELL_PET_HEAL",
	"CHAT_MSG_SPELL_PERIODIC_PET_HEAL",
}
local HEAL_CHAT_EVENTS_SET = {}
for _, evName in ipairs(HEAL_CHAT_EVENTS) do
	HEAL_CHAT_EVENTS_SET[evName] = true
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UNIT_PET")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")

if hasThreatAPI then
	events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
	events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
else
	for evName in pairs(COMBAT_CHAT_EVENTS) do
		events:RegisterEvent(evName)
	end
	for _, evName in ipairs(HEAL_CHAT_EVENTS) do
		events:RegisterEvent(evName)
	end
end

local function UpdateMeter()
	if hasThreatAPI then
		UpdatePreciseMeter()
	else
		UpdateApproxMeter()
	end
end

-- Ручная настройка порога перетягивания агро (команда /ham t <число>).
-- Сохраняется в HunterAggroMeterDB.threshold и подставляется по
-- умолчанию при следующей загрузке аддона.
local function SetAggroThreshold(newValue)
	AGGRO_THRESHOLD = newValue
	HunterAggroMeterDB.threshold = newValue
	thresholdLabel:SetText(AGGRO_THRESHOLD .. "%")
	playerBar:SetMinMaxValues(0, GetBarCap())
	PositionThresholdLine()
	UpdateMeter()
end

-- На некоторых серверах/клиентах SavedVariables подгружаются ПОСЛЕ
-- того, как скрипт аддона уже выполнился один раз — из-за этого
-- сохранённые значения (порог, позиция окна) не применялись сразу
-- при входе. Поэтому на ADDON_LOADED ещё раз перечитываем DB и
-- применяем всё заново.
local function ApplySavedSettings()
	if HunterAggroMeterDB.threshold and HunterAggroMeterDB.threshold ~= AGGRO_THRESHOLD then
		SetAggroThreshold(HunterAggroMeterDB.threshold)
	end

	frame:ClearAllPoints()
	frame:SetPoint(HunterAggroMeterDB.point, UIParent, HunterAggroMeterDB.relPoint, HunterAggroMeterDB.x, HunterAggroMeterDB.y)

	launcher:ClearAllPoints()
	launcher:SetPoint(HunterAggroMeterDB.btnPoint, UIParent, HunterAggroMeterDB.btnRelPoint, HunterAggroMeterDB.btnX, HunterAggroMeterDB.btnY)

	if HunterAggroMeterDB.hidden then
		frame:Hide()
	else
		frame:Show()
	end
end

events:SetScript("OnEvent", function(selfArg, evArg, msgArg, unitArg)
	local ev = evArg or event

	if ev == "ADDON_LOADED" then
		local loadedAddon = msgArg or arg1
		if loadedAddon == ADDON_NAME then
			ApplySavedSettings()
		end
		return
	end

	if ev == "PLAYER_TARGET_CHANGED" then
		if not hasThreatAPI then
			ResetDamageTracking()
		end
		UpdateMeter()
		return
	end

	if ev == "PLAYER_ENTERING_WORLD" then
		ApplySavedSettings()
		UpdateMeter()
		return
	end

	local chatSource = COMBAT_CHAT_EVENTS[ev]
	if chatSource then
		local msg = msgArg or arg1
		HandleCombatChatMsg(chatSource, msg)
		return
	end

	if HEAL_CHAT_EVENTS_SET[ev] then
		local msg = msgArg or arg1
		HandleHealChatMsg(msg)
		return
	end

	if ev == "UNIT_THREAT_LIST_UPDATE" or ev == "UNIT_THREAT_SITUATION_UPDATE" then
		local unit = unitArg or arg1
		if unit and unit ~= "player" and unit ~= "pet" and unit ~= "target" then
			return
		end
	end

	UpdateMeter()
end)

local elapsedSum = 0
frame:SetScript("OnUpdate", function(selfArg, elapsedArg)
	local dt = elapsedArg or arg1 or 0.1

	if not hasThreatAPI then
		CheckFeignDeathState(dt)
	end

	elapsedSum = elapsedSum + dt
	if elapsedSum >= 0.2 then
		elapsedSum = 0
		UpdateMeter()
	end
end)

----------------------------------------------------------------
-- Команды
----------------------------------------------------------------

SLASH_HUNTERAGGROMETER1 = "/ham"
SLASH_HUNTERAGGROMETER2 = "/aggro"
SlashCmdList["HUNTERAGGROMETER"] = function(msg)
	msg = string.lower(msg or "")
	msg = string.gsub(msg, "^%s+", "")
	msg = string.gsub(msg, "%s+$", "")
	if msg == "lock" then
		HunterAggroMeterDB.locked = not HunterAggroMeterDB.locked
		print("|cff33ff99Hunter Aggro Meter|r: window movement " .. (HunterAggroMeterDB.locked and "locked" or "unlocked") .. ".")
	elseif msg == "sound" then
		HunterAggroMeterDB.sound = not HunterAggroMeterDB.sound
		print("|cff33ff99Hunter Aggro Meter|r: sound " .. (HunterAggroMeterDB.sound and "on" or "off") .. ".")
	elseif msg == "reset" then
		HunterAggroMeterDB.point = "CENTER"
		HunterAggroMeterDB.relPoint = "CENTER"
		HunterAggroMeterDB.x = 0
		HunterAggroMeterDB.y = -150
		frame:ClearAllPoints()
		frame:SetPoint(HunterAggroMeterDB.point, UIParent, HunterAggroMeterDB.relPoint, HunterAggroMeterDB.x, HunterAggroMeterDB.y)
		print("|cff33ff99Hunter Aggro Meter|r: window position reset.")
	elseif msg == "show" then
		frame:Show()
		print("|cff33ff99Hunter Aggro Meter|r: window shown.")
	elseif msg == "hide" then
		frame:Hide()
		print("|cff33ff99Hunter Aggro Meter|r: window hidden.")
	elseif msg == "doc" then
		ShowRulesWindow()
	else
		local _, _, cmdWord, numStr = string.find(msg, "^(%a+)%s+(%d+)")
		if (cmdWord == "t" or cmdWord == "threshold") and numStr then
			local num = tonumber(numStr)
			if num and num > 0 then
				SetAggroThreshold(num)
				print("|cff33ff99Hunter Aggro Meter|r: aggro threshold set to " .. num .. "%. Saved, will be used on next login too.")
			else
				print("|cff33ff99Hunter Aggro Meter|r: enter a positive number, e.g. /ham t 180")
			end
			return
		end
		print("|cff33ff99Hunter Aggro Meter|r commands:")
		print("  /ham show      - show the window")
		print("  /ham hide      - hide the window")
		print("  /ham lock      - lock/unlock window position")
		print("  /ham sound     - toggle sound")
		print("  /ham reset     - reset window position")
		print("  /ham t <number> - set aggro threshold %, e.g. /ham t 180")
		print("  /ham doc       - show Rules - read me !")
	end
end
