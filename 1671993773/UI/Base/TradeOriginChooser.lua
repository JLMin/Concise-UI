-- ===========================================================================
--
--	Slideout panel that allows the player to move their trade units to other city centers
--
-- ===========================================================================
include( "InstanceManager" );
include( "AnimSidePanelSupport" );
include( "CitySupport" );
include( "Civ6Common" );
include( "SupportFunctions" );

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID:string = "TradeOriginChooser"; -- Must be unique (usually the same as the file name)

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_AnimSupport:table; --AnimSidePanelSupport

local m_cityIM:table = InstanceManager:new("CityInstance", "Top", Controls.CityStack);

-- CUI
local cui_newCity:table = nil;


-- ===========================================================================
function Refresh()
	-- Find the selected trade unit
	local selectedUnit:table = UI.GetHeadSelectedUnit();
	if selectedUnit == nil then
		Close();
		return;
	end

	-- Find the current city
	local originCity = Cities.GetCityInPlot(selectedUnit:GetX(), selectedUnit:GetY());
	if originCity == nil then
		Close();
		return;
	end
  
  CuiRefreshHeader(); -- CUI

	-- Reset Instance Manager
	m_cityIM:ResetInstances();

	-- Add all other cities to city stack
	local localPlayer = Players[Game.GetLocalPlayer()];
	local playerCities:table = localPlayer:GetCities();
	for _, city in playerCities:Members() do
		if city ~= originCity and CanTeleportToCity(city) then
			AddCity(city);
		end
	end

	-- Calculate Control Size
	Controls.CityScrollPanel:CalculateInternalSize();
	Controls.CityStack:CalculateSize();
	Controls.CityStack:ReprocessAnchoring();
end

-- ===========================================================================
function AddCity(city:table)
	local cityInstance:table = m_cityIM:GetInstance();
  cityInstance.SelectorBrace:SetColor(1,1,1,0);
  
  -- CUI: add city info
  ----------------------------------------------------------------------------
  local backColor:number, frontColor:number = UI.GetPlayerColors(Game.GetLocalPlayer());
  cityInstance.BannerBase:SetColor(backColor);
  
  -- religion icon
  local cityMajorityReligion = city:GetReligion():GetMajorityReligion();
  if (cityMajorityReligion > 0) then
    local religionInfo:table = GameInfo.Religions[cityMajorityReligion];
    local religionColor = UI.GetColorValue(religionInfo.Color);
    local religionName = Game.GetReligion():GetName(religionInfo.Index);
    cityInstance.ReligionIcon:SetIcon("ICON_" .. religionInfo.ReligionType);
    cityInstance.ReligionIcon:SetColor(religionColor);
    cityInstance.ReligionIconBacking:SetColor(religionColor);
    cityInstance.ReligionIconBacking:SetToolTipString(religionName);
  end
  
  -- city name
  cityInstance.CityName:SetColor(frontColor);
	cityInstance.CityName:SetText(Locale.ToUpper(city:GetName()));
    
  -- population
  cityInstance.CityPopulation:SetColor(frontColor);
  cityInstance.CityPopulation:SetText("[ICON_Citizen] " .. city:GetPopulation());
  
  -- yields
  local yields = CuiGetCityYieldPerTurn(city, 0);
  cityInstance.CityFood      :SetText(yields.FoodPT);
  cityInstance.CityProduction:SetText(yields.ProductionPT);
  cityInstance.CityGold      :SetText(yields.GoldPT);
  cityInstance.CityScience   :SetText(yields.SciencePT);
  cityInstance.CityCulture   :SetText(yields.CulturePT);
  cityInstance.CityFaith     :SetText(yields.FaithPT);
  
  -- CUI: button adjust
  if cui_newCity ~= nil and cui_newCity == city then
    cityInstance.SelectorBrace:SetColor(1,1,1,1);
    cityInstance.Button:SetSelected(true);
  else
    cityInstance.SelectorBrace:SetColor(1,1,1,0);
    cityInstance.Button:SetSelected(false);
  end
  cityInstance.Button:RegisterCallback(Mouse.eLClick,
    function()
      cui_newCity = city;
      CuiRealizeLookAtCity(city);
      Refresh();
    end);
end

-- ===========================================================================
function CanTeleportToCity(city:table)
	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_X] = city:GetX();
	tParameters[UnitOperationTypes.PARAM_Y] = city:GetY();

	local eOperation = UI.GetInterfaceModeParameter(UnitOperationTypes.PARAM_OPERATION_TYPE);

	local pSelectedUnit = UI.GetHeadSelectedUnit();
	if (UnitManager.CanStartOperation( pSelectedUnit, eOperation, nil, tParameters)) then
		return true;
	end

	return false;
end

-- ===========================================================================
function TeleportToCity(city:table)
	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_X] = city:GetX();
	tParameters[UnitOperationTypes.PARAM_Y] = city:GetY();

	local eOperation = UI.GetInterfaceModeParameter(UnitOperationTypes.PARAM_OPERATION_TYPE);

	local pSelectedUnit = UI.GetHeadSelectedUnit();
	if (UnitManager.CanStartOperation( pSelectedUnit, eOperation, nil, tParameters)) then
		UnitManager.RequestOperation( pSelectedUnit, eOperation, tParameters);
		UI.SetInterfaceMode(InterfaceModeTypes.SELECTION);
        UI.PlaySound("Unit_Relocate");
		Close();
	end
end

-- ===========================================================================
function OnInterfaceModeChanged( oldMode:number, newMode:number )
	if (oldMode == InterfaceModeTypes.TELEPORT_TO_CITY) then
		-- Only close if already open
		if m_AnimSupport:IsVisible() then
			Close();
		end
	end
	if (newMode == InterfaceModeTypes.TELEPORT_TO_CITY) then
		-- Only open if selected unit is a trade unit
		local pSelectedUnit:table = UI.GetHeadSelectedUnit();
		local pSelectedUnitInfo:table = GameInfo.Units[pSelectedUnit:GetUnitType()];
		if pSelectedUnitInfo.MakeTradeRoute then
			Open();
		end
	end
end

-- ===========================================================================
function OnCitySelectionChanged(owner, ID, i, j, k, bSelected, bEditable)
	-- Close if we select a city
	if m_AnimSupport:IsVisible() and owner == Game.GetLocalPlayer() and owner ~= -1 then
		Close();
	end
end

-- ===========================================================================
function OnUnitSelectionChanged( playerID : number, unitID : number, hexI : number, hexJ : number, hexK : number, bSelected : boolean, bEditable : boolean)
	-- Close if we select a unit
	if m_AnimSupport:IsVisible() and playerID ~= -1 and playerID == Game.GetLocalPlayer() then
		Close();
	end
end

------------------------------------------------------------------------------------------------
function OnLocalPlayerTurnEnd()
	if(GameConfiguration.IsHotseat()) then
		Close();
	end
end

-- ===========================================================================
function Open()
	LuaEvents.TradeOriginChooser_SetTradeUnitStatus("LOC_HUD_UNIT_PANEL_CHOOSING_ORIGIN_CITY");
	m_AnimSupport:Show();
	Refresh();
end

-- ===========================================================================
function Close()
	LuaEvents.TradeOriginChooser_SetTradeUnitStatus("");
	m_AnimSupport:Hide();
end

-- ===========================================================================
function OnOpen()
  cui_newCity = nil; -- CUI
	Open();
end

-- ===========================================================================
function OnClose()
  cui_newCity = nil; -- CUI
	Close();
end

-- ===========================================================================
--	HOT-RELOADING EVENTS
-- ===========================================================================
function OnInit(isReload:boolean)
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	end
end
function OnShutdown()
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isVisible", m_AnimSupport:IsVisible());
end
function OnGameDebugReturn(context:string, contextTable:table)
	if context == RELOAD_CACHE_ID and contextTable["isVisible"] ~= nil and contextTable["isVisible"] then
		OnOpen();
	end
end

-- CUI =======================================================================
function CuiRefreshHeader()
  if cui_newCity then
    Controls.CurrentSelectionContainer:SetHide(false);
    Controls.ChangeOriginCityButton:SetHide(false);
    Controls.StatusMessage:SetHide(true);
    Controls.MoveToAnim:SetToBeginning();
    Controls.MoveToAnim:Play();

    local backColor:number, frontColor:number = UI.GetPlayerColors(Game.GetLocalPlayer());
    Controls.BannerBase:SetColor(backColor);
    Controls.CityName:SetColor(frontColor);
    Controls.CityName:SetText(Locale.ToUpper(cui_newCity:GetName()));
  else
    Controls.CurrentSelectionContainer:SetHide(true);
    Controls.ChangeOriginCityButton:SetHide(true);
    Controls.StatusMessage:SetHide(false);
    Controls.MoveToAnim:Stop();
    Controls.MoveToAnim:SetToBeginning();
  end
end

-- CUI =======================================================================
function CuiRealizeLookAtCity(city)
  local locX:number = city:GetX();
  local locY:number = city:GetY();
  UI.LookAtPlotScreenPosition( locX, locY, 0.5, 0.5 );
end

-- CUI =======================================================================
function CuiOnChangeOriginCity()
  if cui_newCity then TeleportToCity(cui_newCity); end
end

-- CUI =======================================================================
function CuiGetCityYieldPerTurn(city:table, round:number)
  local yields:table = {};

  local data:table = GetCityData( city );
  local iModifiedFood;
  local totalFood:number;
  if data.TurnsUntilGrowth > -1 then
    local growthModifier =  math.max(1 + (data.HappinessGrowthModifier/100) + data.OtherGrowthModifiers, 0);
    iModifiedFood = Round(data.FoodSurplus * growthModifier, 2);
    if data.Occupied then
      totalFood = iModifiedFood * data.OccupationMultiplier;
    else
      totalFood = iModifiedFood * data.HousingMultiplier;
    end
  else
    totalFood = data.FoodSurplus;
  end

  local n = round == nil and 1 or round;
  yields.FoodPT       = Round(totalFood, n);
  yields.ProductionPT = Round(data.ProductionPerTurn, n);
  yields.GoldPT       = Round(data.GoldPerTurn, n);
  yields.SciencePT    = Round(data.SciencePerTurn, n);
  yields.CulturePT    = Round(data.CulturePerTurn, n);
  yields.FaithPT      = Round(data.FaithPerTurn, n);

  return yields;
end

-- CUI =======================================================================
function CuiInit()
  -- UI init
  Controls.Header:SetHide(true);
  Controls.Background:SetHide(true);
  Controls.ReplaceTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UNITOPERATION_MOVE_TO_DESCRIPTION")));
  -- reg
  Controls.ChangeOriginCityButton:RegisterCallback(Mouse.eLClick, CuiOnChangeOriginCity);
  Controls.ChangeOriginCityButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
end

-- ===========================================================================
--	INIT
-- ===========================================================================
function Initialize()
  
  CuiInit(); -- CUI

	-- Hot-reload events
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
	
	LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);

	-- Game Engine Events	
	Events.InterfaceModeChanged.Add( OnInterfaceModeChanged );
	Events.CitySelectionChanged.Add( OnCitySelectionChanged );
	Events.UnitSelectionChanged.Add( OnUnitSelectionChanged );	
	Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );

	-- Animation controller
	m_AnimSupport = CreateScreenAnimation(Controls.SlideAnim);

	-- Animation controller events
	Events.SystemUpdateUI.Add(m_AnimSupport.OnUpdateUI);
	ContextPtr:SetInputHandler(m_AnimSupport.OnInputHandler, true);

	-- Control Events
	Controls.CloseButton:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
end
Initialize();