-- Copyright 2016-2018, Firaxis Games

include("CitySupport");
include("Civ6Common");
include("InstanceManager");
include("SupportFunctions");
include("TabSupport");
include("CuiHelper"); -- CUI
include("CuiSettings"); -- CUI

-- ===========================================================================
--	DEBUG
--	Toggle these for temporary debugging help.
-- ===========================================================================
local m_debugNumResourcesStrategic	:number = 0;			-- (0) number of extra strategics to show for screen testing.
local m_debugNumBonuses				:number = 0;			-- (0) number of extra bonuses to show for screen testing.
local m_debugNumResourcesLuxuries	:number = 0;			-- (0) number of extra luxuries to show for screen testing.


-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local DARKEN_CITY_INCOME_AREA_ADDITIONAL_Y		:number = 6;
local DATA_FIELD_SELECTION						:string = "Selection";
local SIZE_HEIGHT_BOTTOM_YIELDS					:number = 135;
local SIZE_HEIGHT_PADDING_BOTTOM_ADJUST			:number = 85;	-- (Total Y - (scroll area + THIS PADDING)) = bottom area
local INDENT_STRING								:string = "        ";

-- Mapping of unit type to cost.
local UnitCostMap:table = {};
do
  for row in GameInfo.Units() do
    UnitCostMap[row.UnitType] = row.Maintenance;
  end
end


-- ===========================================================================
--	VARIABLES
-- ===========================================================================

m_simpleIM							= InstanceManager:new("SimpleInstance",			"Top",		Controls.Stack);				-- Non-Collapsable, simple
m_tabIM								= InstanceManager:new("TabInstance",				"Button",	Controls.TabContainer);
m_strategicResourcesIM				= InstanceManager:new("ResourceAmountInstance",	"Info",		Controls.StrategicResources);
m_bonusResourcesIM					= InstanceManager:new("ResourceAmountInstance",	"Info",		Controls.BonusResources);
m_luxuryResourcesIM					= InstanceManager:new("ResourceAmountInstance",	"Info",		Controls.LuxuryResources);
local m_groupIM				:table	= InstanceManager:new("GroupInstance",			"Top",		Controls.Stack);				-- Collapsable


m_kCityData = nil;
m_tabs = nil;
m_kResourceData = nil;
local m_kCityTotalData		:table = nil;
local m_kUnitData			:table = nil;	-- TODO: Show units by promotion class
local m_kDealData			:table = nil;
local m_uiGroups			:table = nil;	-- Track the groups on-screen for collapse all action.

local m_isCollapsing		:boolean = true;

-- CUI Variables =============================================================
local cui_ShowCityDetail:boolean = false;
local cui_ShowStrategic :boolean = true;
local cui_ShowLuxury    :boolean = true;
local cui_ShowBonus     :boolean = false;
local cui_CurrentDeals	:table   = nil;

-- ===========================================================================
--	Single exit point for display
-- ===========================================================================
function Close()
  if not ContextPtr:IsHidden() then
    UI.PlaySound("UI_Screen_Close");
  end

  UIManager:DequeuePopup(ContextPtr);
end


-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnCloseButton()
  Close();
end

-- ===========================================================================
--	Single entry point for display
-- ===========================================================================
function Open( tabToOpen:string )
  
  local displayedTabIndex:number = 1;
  if tabToOpen == "Resources"  then displayedTabIndex = 2; end
  if tabToOpen == "CityStatus" then displayedTabIndex = 3; end
  if tabToOpen == "Deals"      then displayedTabIndex = 4; end -- CUI
  
  UIManager:QueuePopup( ContextPtr, PopupPriority.Medium );
  Controls.ScreenAnimIn:SetToBeginning();
  Controls.ScreenAnimIn:Play();
  UI.PlaySound("UI_Screen_Open");

  m_kCityData, m_kCityTotalData, m_kResourceData, m_kUnitData, m_kDealData, cui_CurrentDeals = GetData();
  
  m_tabs.SelectTab( displayedTabIndex );
end

-- ===========================================================================
--	LUA Events
--	Opened via the top panel
-- ===========================================================================
function OnTopOpenReportsScreen()
  Open();
end

-- ===========================================================================
--	LUA Events
-- ===========================================================================
function OnOpenCityStatus()
  Open("CityStatus");
end

-- ===========================================================================
--	LUA Events
-- ===========================================================================
function OnOpenResources()
  Open("Resources");
end

-- ===========================================================================
--	LUA Events -- CUI
-- ===========================================================================
function OnOpenDeals()
  Open("Deals");
end

-- ===========================================================================
--	LUA Events
--	Closed via the top panel
-- ===========================================================================
function OnTopCloseReportsScreen()
  Close();	
end

-- ===========================================================================
--	UI Callback
--	Collapse all the things!
-- ===========================================================================
function OnCollapseAllButton()
  if m_uiGroups == nil or table.count(m_uiGroups) == 0 then
    return;
  end

  for i,instance in ipairs( m_uiGroups ) do
    if instance["isCollapsed"] ~= m_isCollapsing then
      instance["isCollapsed"] = m_isCollapsing;
      instance.CollapseAnim:Reverse();
      RealizeGroup( instance );
    end
  end
  Controls.CollapseAll:LocalizeAndSetText(m_isCollapsing and "LOC_HUD_REPORTS_EXPAND_ALL" or "LOC_HUD_REPORTS_COLLAPSE_ALL");
  m_isCollapsing = not m_isCollapsing;
end

-- ===========================================================================
--	Populate with all data required for any/all report tabs.
-- ===========================================================================
function GetData()
  local kResources	:table = {};
  local kCityData		:table = {};
  local kCityTotalData:table = {
    Income	= {},
    Expenses= {},
    Net		= {},
    Treasury= {}
  };
  local kUnitData		:table = {};


  kCityTotalData.Income[YieldTypes.CULTURE]	= 0;
  kCityTotalData.Income[YieldTypes.FAITH]		= 0;
  kCityTotalData.Income[YieldTypes.FOOD]		= 0;
  kCityTotalData.Income[YieldTypes.GOLD]		= 0;
  kCityTotalData.Income[YieldTypes.PRODUCTION]= 0;
  kCityTotalData.Income[YieldTypes.SCIENCE]	= 0;
  kCityTotalData.Income["TOURISM"]			= 0;
  kCityTotalData.Expenses[YieldTypes.GOLD]	= 0;
  
  local playerID	:number = Game.GetLocalPlayer();
  if playerID == PlayerTypes.NONE then
    UI.DataError("Unable to get valid playerID for report screen.");
    return;
  end

  local player	:table  = Players[playerID];
  local pCulture	:table	= player:GetCulture();
  local pTreasury	:table	= player:GetTreasury();
  local pReligion	:table	= player:GetReligion();
  local pScience	:table	= player:GetTechs();
  local pResources:table	= player:GetResources();		

  local pCities = player:GetCities();
  for i, pCity in pCities:Members() do	
    local cityName	:string = pCity:GetName();
      
    -- Big calls, obtain city data and add report specific fields to it.
    local data		:table	= GetCityData( pCity );
    data.Resources			= GetCityResourceData( pCity );					-- Add more data (not in CitySupport)			
    data.WorkedTileYields	= GetWorkedTileYieldData( pCity, pCulture );	-- Add more data (not in CitySupport)

    -- Add to totals.
    kCityTotalData.Income[YieldTypes.CULTURE]	= kCityTotalData.Income[YieldTypes.CULTURE] + data.CulturePerTurn;
    kCityTotalData.Income[YieldTypes.FAITH]		= kCityTotalData.Income[YieldTypes.FAITH] + data.FaithPerTurn;
    kCityTotalData.Income[YieldTypes.FOOD]		= kCityTotalData.Income[YieldTypes.FOOD] + data.FoodPerTurn;
    kCityTotalData.Income[YieldTypes.GOLD]		= kCityTotalData.Income[YieldTypes.GOLD] + data.GoldPerTurn;
    kCityTotalData.Income[YieldTypes.PRODUCTION]= kCityTotalData.Income[YieldTypes.PRODUCTION] + data.ProductionPerTurn;
    kCityTotalData.Income[YieldTypes.SCIENCE]	= kCityTotalData.Income[YieldTypes.SCIENCE] + data.SciencePerTurn;
    kCityTotalData.Income["TOURISM"]			= kCityTotalData.Income["TOURISM"] + data.WorkedTileYields["TOURISM"];
      
    kCityData[cityName] = data;

    -- Add outgoing route data
    data.OutgoingRoutes = pCity:GetTrade():GetOutgoingRoutes();

    -- Add resources
    if m_debugNumResourcesStrategic > 0 or m_debugNumResourcesLuxuries > 0 or m_debugNumBonuses > 0 then
      for debugRes=1,m_debugNumResourcesStrategic,1 do
        kResources[debugRes] = {
          CityList	= { CityName="Kangaroo", Amount=(10+debugRes) },
          Icon		= "[ICON_"..GameInfo.Resources[debugRes].ResourceType.."]",
          IsStrategic	= true,
          IsLuxury	= false,
          IsBonus		= false,
          Total		= 88
        };
      end
      for debugRes=1,m_debugNumResourcesLuxuries,1 do
        kResources[debugRes] = {
          CityList	= { CityName="Kangaroo", Amount=(10+debugRes) },
          Icon		= "[ICON_"..GameInfo.Resources[debugRes].ResourceType.."]",
          IsStrategic	= false,
          IsLuxury	= true,
          IsBonus		= false,
          Total		= 88
        };
      end
      for debugRes=1,m_debugNumBonuses,1 do
        kResources[debugRes] = {
          CityList	= { CityName="Kangaroo", Amount=(10+debugRes) },
          Icon		= "[ICON_"..GameInfo.Resources[debugRes].ResourceType.."]",
          IsStrategic	= false,
          IsLuxury	= false,
          IsBonus		= true,
          Total		= 88
        };
      end
    end

    for eResourceType,amount in pairs(data.Resources) do
      AddResourceData(kResources, eResourceType, cityName, "LOC_HUD_REPORTS_TRADE_OWNED", amount);
    end

    -- CUI: add garrisoned unit icon
    local pPlotCity:table = Map.GetPlot( pCity:GetX(), pCity:GetY() );
    for _, unit in ipairs(Units.GetUnitsInPlot(pPlotCity)) do
      local unitInfo:table = GameInfo.Units[unit:GetUnitType()];
      local formationClass:string = unitInfo.FormationClass;
      if formationClass == "FORMATION_CLASS_LAND_COMBAT" then
        data.GarrisonUnitIcon = "ICON_" .. unitInfo.UnitType;
        data.GarrisonUnitName = Locale.Lookup(unit:GetName());
        break;
      else
        data.GarrisonUnitIcon = "";
        data.GarrisonUnitName = "";
      end
    end
  end

  kCityTotalData.Expenses[YieldTypes.GOLD] = pTreasury:GetTotalMaintenance();

  -- NET = Income - Expense
  kCityTotalData.Net[YieldTypes.GOLD]			= kCityTotalData.Income[YieldTypes.GOLD] - kCityTotalData.Expenses[YieldTypes.GOLD];
  kCityTotalData.Net[YieldTypes.FAITH]		= kCityTotalData.Income[YieldTypes.FAITH];

  -- Treasury
  kCityTotalData.Treasury[YieldTypes.CULTURE]		= Round( pCulture:GetCultureYield(), 0 );
  kCityTotalData.Treasury[YieldTypes.FAITH]		= Round( pReligion:GetFaithBalance(), 0 );
  kCityTotalData.Treasury[YieldTypes.GOLD]		= Round( pTreasury:GetGoldBalance(), 0 );
  kCityTotalData.Treasury[YieldTypes.SCIENCE]		= Round( pScience:GetScienceYield(), 0 );
  kCityTotalData.Treasury["TOURISM"]				= Round( kCityTotalData.Income["TOURISM"], 0 );


  -- Units (TODO: Group units by promotion class and determine total maintenance cost)
  local MaintenanceDiscountPerUnit:number = pTreasury:GetMaintDiscountPerUnit();
  local pUnits :table = player:GetUnits(); 	
  for i, pUnit in pUnits:Members() do
    local pUnitInfo:table = GameInfo.Units[pUnit:GetUnitType()];
    local unitTypeKey = pUnitInfo.UnitType;
    local TotalMaintenanceAfterDiscount:number = 0;
    local unitMaintenance = 0;
    local unitName :string = Locale.Lookup(pUnitInfo.Name);
    local unitMilitaryFormation = pUnit:GetMilitaryFormation();
    unitTypeKey = unitTypeKey .. unitMilitaryFormation;
    if (pUnitInfo.Domain == "DOMAIN_SEA") then
      if (unitMilitaryFormation == MilitaryFormationTypes.CORPS_FORMATION) then
        unitName = unitName .. " " .. Locale.Lookup("LOC_HUD_UNIT_PANEL_FLEET_SUFFIX");
        unitMaintenance = UnitManager.GetUnitCorpsMaintenance(pUnitInfo.Hash);
      elseif (unitMilitaryFormation == MilitaryFormationTypes.ARMY_FORMATION) then
        unitName = unitName .. " " .. Locale.Lookup("LOC_HUD_UNIT_PANEL_ARMADA_SUFFIX");
        unitMaintenance = UnitManager.GetUnitArmyMaintenance(pUnitInfo.Hash);
      else
        unitMaintenance = UnitManager.GetUnitMaintenance(pUnitInfo.Hash);
      end
    else
      if (unitMilitaryFormation == MilitaryFormationTypes.CORPS_FORMATION) then
        unitName = unitName .. " " .. Locale.Lookup("LOC_HUD_UNIT_PANEL_CORPS_SUFFIX");
        unitMaintenance = UnitManager.GetUnitCorpsMaintenance(pUnitInfo.Hash);
      elseif (unitMilitaryFormation == MilitaryFormationTypes.ARMY_FORMATION) then
        unitName = unitName .. " " .. Locale.Lookup("LOC_HUD_UNIT_PANEL_ARMY_SUFFIX");
        unitMaintenance = UnitManager.GetUnitArmyMaintenance(pUnitInfo.Hash);
      else
        unitMaintenance = UnitManager.GetUnitMaintenance(pUnitInfo.Hash);
      end
    end

    if (unitMaintenance > 0) then
      TotalMaintenanceAfterDiscount = unitMaintenance - MaintenanceDiscountPerUnit; 
    end
    if TotalMaintenanceAfterDiscount > 0 then
      if kUnitData[unitTypeKey] == nil then
        local UnitEntry:table = {};
        UnitEntry.Name = unitName;
        UnitEntry.Count = 1;
        UnitEntry.Maintenance = TotalMaintenanceAfterDiscount;
        kUnitData[unitTypeKey]= UnitEntry;
      else
        kUnitData[unitTypeKey].Count = kUnitData[unitTypeKey].Count + 1;
        kUnitData[unitTypeKey].Maintenance = kUnitData[unitTypeKey].Maintenance + TotalMaintenanceAfterDiscount;
      end
    end
  end

  -- =================================================================
  -- CUI Deal page data
  -- =================================================================
  local kCurrentDeals : table = {}
  local kPlayers : table = PlayerManager.GetAliveMajors()
  local iTotal = 0

  for _, pOtherPlayer in ipairs( kPlayers ) do
    local otherID:number = pOtherPlayer:GetID()
    if  otherID ~= playerID then

      local pPlayerConfig	:table = PlayerConfigurations[otherID]
      local pDeals		:table = DealManager.GetPlayerDeals( playerID, otherID )

      if pDeals ~= nil then

        for i, pDeal in ipairs( pDeals ) do
          iTotal = iTotal + 1

          local Receiving : table = { Agreements = {}, Gold = {}, Resources = {} }
          local Sending : table = { Agreements = {}, Gold = {}, Resources = {} }

          Receiving.Resources = pDeal:FindItemsByType( DealItemTypes.RESOURCES, DealItemSubTypes.NONE, otherID )
          Receiving.Gold = pDeal:FindItemsByType( DealItemTypes.GOLD, DealItemSubTypes.NONE, otherID )
          Receiving.Agreements = pDeal:FindItemsByType( DealItemTypes.AGREEMENTS, DealItemSubTypes.NONE, otherID )

          Sending.Resources = pDeal:FindItemsByType( DealItemTypes.RESOURCES, DealItemSubTypes.NONE, playerID )
          Sending.Gold = pDeal:FindItemsByType( DealItemTypes.GOLD, DealItemSubTypes.NONE, playerID )
          Sending.Agreements = pDeal:FindItemsByType( DealItemTypes.AGREEMENTS, DealItemSubTypes.NONE, playerID )

          kCurrentDeals[iTotal] =
          {
            WithCivilization = Locale.Lookup( pPlayerConfig:GetCivilizationDescription() ),
            EndTurn = 0,
            Receiving = {},
            Sending = {}
          }

          local iDeal = 0

          for pReceivingName, pReceivingGroup in pairs( Receiving ) do
            for _, pDealItem in ipairs( pReceivingGroup ) do

              iDeal = iDeal + 1

              kCurrentDeals[iTotal].EndTurn = pDealItem:GetEndTurn()
              kCurrentDeals[iTotal].Receiving[iDeal] = { Amount = pDealItem:GetAmount() }

              local deal = kCurrentDeals[iTotal].Receiving[iDeal]

              if pReceivingName == "Agreements" then
                deal.Name = pDealItem:GetSubTypeNameID()
              elseif pReceivingName == "Gold" then
                deal.Name = deal.Amount.." "..Locale.Lookup("LOC_DIPLOMACY_DEAL_GOLD_PER_TURN");
                deal.Icon = "[ICON_GOLD]"
              else
                if deal.Amount > 1 then
                  deal.Name = pDealItem:GetValueTypeNameID() .. "(" .. deal.Amount .. ")"
                else
                  deal.Name = pDealItem:GetValueTypeNameID()
                end
                deal.Icon = "[ICON_" .. pDealItem:GetValueTypeID() .. "]"
              end

              deal.Name = Locale.Lookup( deal.Name )
            end
          end

          iDeal = 0

          for pSendingName, pSendingGroup in pairs( Sending ) do
            for _, pDealItem in ipairs( pSendingGroup ) do

              iDeal = iDeal + 1

              kCurrentDeals[iTotal].EndTurn = pDealItem:GetEndTurn()
              kCurrentDeals[iTotal].Sending[iDeal] = { Amount = pDealItem:GetAmount() }

              local deal = kCurrentDeals[iTotal].Sending[iDeal]

              if pSendingName == "Agreements" then
                deal.Name = pDealItem:GetSubTypeNameID()
              elseif pSendingName == "Gold" then
                deal.Name = deal.Amount.." "..Locale.Lookup("LOC_DIPLOMACY_DEAL_GOLD_PER_TURN");
                deal.Icon = "[ICON_GOLD]"
              else
                if deal.Amount > 1 then
                  deal.Name = pDealItem:GetValueTypeNameID() .. "(" .. deal.Amount .. ")"
                else
                  deal.Name = pDealItem:GetValueTypeNameID()
                end
                deal.Icon = "[ICON_" .. pDealItem:GetValueTypeID() .. "]"
              end

              deal.Name = Locale.Lookup( deal.Name )
            end
          end
        end
      end
    end
  end

  -- =================================================================
  local kDealData	:table = {};
  local kPlayers	:table = PlayerManager.GetAliveMajors();
  for _, pOtherPlayer in ipairs(kPlayers) do
    local otherID:number = pOtherPlayer:GetID();
    local currentGameTurn = Game.GetCurrentGameTurn();
    if  otherID ~= playerID then			
      
      local pPlayerConfig	:table = PlayerConfigurations[otherID];
      local pDeals		:table = DealManager.GetPlayerDeals(playerID, otherID);
      
      if pDeals ~= nil then
        for i,pDeal in ipairs(pDeals) do
          -- Add outgoing gold deals
          local pOutgoingDeal :table	= pDeal:FindItemsByType(DealItemTypes.GOLD, DealItemSubTypes.NONE, playerID);
          if pOutgoingDeal ~= nil then
            for i,pDealItem in ipairs(pOutgoingDeal) do
              local duration		:number = pDealItem:GetDuration();
              local remainingTurns:number = duration - (currentGameTurn - pDealItem:GetEnactedTurn());
              if duration ~= 0 then
                local gold :number = pDealItem:GetAmount();
                table.insert( kDealData, {
                  Type		= DealItemTypes.GOLD,
                  Amount		= gold,
                  Duration	= remainingTurns,
                  IsOutgoing	= true,
                  PlayerID	= otherID,
                  Name		= Locale.Lookup( pPlayerConfig:GetCivilizationDescription() )
                });						
              end
            end
          end

          -- Add outgoing resource deals
          pOutgoingDeal = pDeal:FindItemsByType(DealItemTypes.RESOURCES, DealItemSubTypes.NONE, playerID);
          if pOutgoingDeal ~= nil then
            for i,pDealItem in ipairs(pOutgoingDeal) do
              local duration		:number = pDealItem:GetDuration();
              local remainingTurns:number = duration - (currentGameTurn - pDealItem:GetEnactedTurn());
              if duration ~= 0 then
                local amount		:number = pDealItem:GetAmount();
                local resourceType	:number = pDealItem:GetValueType();
                table.insert( kDealData, {
                  Type			= DealItemTypes.RESOURCES,
                  ResourceType	= resourceType,
                  Amount			= amount,
                  Duration		= remainingTurns,
                  IsOutgoing		= true,
                  PlayerID		= otherID,
                  Name			= Locale.Lookup( pPlayerConfig:GetCivilizationDescription() )
                });
                
                local entryString:string = Locale.Lookup("LOC_HUD_REPORTS_ROW_DIPLOMATIC_DEALS") .. " (" .. Locale.Lookup(pPlayerConfig:GetPlayerName()) .. " " .. Locale.Lookup("LOC_REPORTS_NUMBER_OF_TURNS", remainingTurns) .. ")";
                AddResourceData(kResources, resourceType, entryString, "LOC_HUD_REPORTS_TRADE_EXPORTED", -1 * amount);				
              end
            end
          end
          
          -- Add incoming gold deals
          local pIncomingDeal :table = pDeal:FindItemsByType(DealItemTypes.GOLD, DealItemSubTypes.NONE, otherID);
          if pIncomingDeal ~= nil then
            for i,pDealItem in ipairs(pIncomingDeal) do
              local duration		:number = pDealItem:GetDuration();
              local remainingTurns:number = duration - (currentGameTurn - pDealItem:GetEnactedTurn());
              if duration ~= 0 then
                local gold :number = pDealItem:GetAmount()
                table.insert( kDealData, {
                  Type		= DealItemTypes.GOLD;
                  Amount		= gold,
                  Duration	= remainingTurns,
                  IsOutgoing	= false,
                  PlayerID	= otherID,
                  Name		= Locale.Lookup( pPlayerConfig:GetCivilizationDescription() )
                });						
              end
            end
          end

          -- Add incoming resource deals
          pIncomingDeal = pDeal:FindItemsByType(DealItemTypes.RESOURCES, DealItemSubTypes.NONE, otherID);
          if pIncomingDeal ~= nil then
            for i,pDealItem in ipairs(pIncomingDeal) do
              local duration		:number = pDealItem:GetDuration();
              if duration ~= 0 then
                local amount		:number = pDealItem:GetAmount();
                local resourceType	:number = pDealItem:GetValueType();
                local remainingTurns:number = duration - (currentGameTurn - pDealItem:GetEnactedTurn());
                table.insert( kDealData, {
                  Type			= DealItemTypes.RESOURCES,
                  ResourceType	= resourceType,
                  Amount			= amount,
                  Duration		= remainingTurns,
                  IsOutgoing		= false,
                  PlayerID		= otherID,
                  Name			= Locale.Lookup( pPlayerConfig:GetCivilizationDescription() )
                });
                
                local entryString:string = Locale.Lookup("LOC_HUD_REPORTS_ROW_DIPLOMATIC_DEALS") .. " (" .. Locale.Lookup(pPlayerConfig:GetPlayerName()) .. " " .. Locale.Lookup("LOC_REPORTS_NUMBER_OF_TURNS", remainingTurns) .. ")";
                AddResourceData(kResources, resourceType, entryString, "LOC_HUD_REPORTS_TRADE_IMPORTED", amount);				
              end
            end
          end	
        end							
      end

    end
  end

  -- Add resources provided by city states
  for i, pMinorPlayer in ipairs(PlayerManager.GetAliveMinors()) do
    local pMinorPlayerInfluence:table = pMinorPlayer:GetInfluence();		
    if pMinorPlayerInfluence ~= nil then
      local suzerainID:number = pMinorPlayerInfluence:GetSuzerain();
      if suzerainID == playerID then
        for row in GameInfo.Resources() do
          local resourceAmount:number =  pMinorPlayer:GetResources():GetExportedResourceAmount(row.Index);
          if resourceAmount > 0 then
            local pMinorPlayerConfig:table = PlayerConfigurations[pMinorPlayer:GetID()];
            local entryString:string = Locale.Lookup("LOC_HUD_REPORTS_CITY_STATE") .. " (" .. Locale.Lookup(pMinorPlayerConfig:GetPlayerName()) .. ")";
            AddResourceData(kResources, row.Index, entryString, "LOC_CITY_STATES_SUZERAIN", resourceAmount);
          end
        end
      end
    end
  end

  kResources = AddMiscResourceData(pResources, kResources);

  return kCityData, kCityTotalData, kResources, kUnitData, kDealData, kCurrentDeals;
end

function AddMiscResourceData(pResourceData:table, kResourceTable:table)
  -- Resources not yet accounted for come from other gameplay bonuses
  if pResourceData then
    for row in GameInfo.Resources() do
      local internalResourceAmount:number = pResourceData:GetResourceAmount(row.Index);
      if (internalResourceAmount > 0) then
        if (kResourceTable[row.Index] ~= nil) then
          if (internalResourceAmount > kResourceTable[row.Index].Total) then
            AddResourceData(kResourceTable, row.Index, "LOC_HUD_REPORTS_MISC_RESOURCE_SOURCE", "-", internalResourceAmount - kResourceTable[row.Index].Total);
          end
        else
          AddResourceData(kResourceTable, row.Index, "LOC_HUD_REPORTS_MISC_RESOURCE_SOURCE", "-", internalResourceAmount);
        end
      end
    end
  end
  return kResourceTable;
end

-- ===========================================================================
function AddResourceData( kResources:table, eResourceType:number, EntryString:string, ControlString:string, InAmount:number)
  local kResource :table = GameInfo.Resources[eResourceType];

  --Artifacts need to be excluded because while TECHNICALLY a resource, they do nothing to contribute in a way that is relevant to any other resource 
  --or screen. So... exclusion.
  if kResource.ResourceClassType == "RESOURCECLASS_ARTIFACT" then
    return;
  end

  if kResources[eResourceType] == nil then
    kResources[eResourceType] = {
      EntryList	= {},
      Icon		= "[ICON_"..kResource.ResourceType.."]",
      IsStrategic	= kResource.ResourceClassType == "RESOURCECLASS_STRATEGIC",
      IsLuxury	= GameInfo.Resources[eResourceType].ResourceClassType == "RESOURCECLASS_LUXURY",
      IsBonus		= GameInfo.Resources[eResourceType].ResourceClassType == "RESOURCECLASS_BONUS",
      Total		= 0
    };
  end

  table.insert( kResources[eResourceType].EntryList, 
  {
    EntryText	= EntryString,
    ControlText = ControlString,
    Amount		= InAmount,					
  });

  kResources[eResourceType].Total = kResources[eResourceType].Total + InAmount;
end

-- ===========================================================================
--	Obtain the total resources for a given city.
-- ===========================================================================
function GetCityResourceData( pCity:table )

  -- Loop through all the plots for a given city; tallying the resource amount.
  local kResources : table = {};
  local cityPlots : table = Map.GetCityPlots():GetPurchasedPlots(pCity)
  for _, plotID in ipairs(cityPlots) do
    local plot			: table = Map.GetPlotByIndex(plotID)
    local plotX			: number = plot:GetX()
    local plotY			: number = plot:GetY()
    local eResourceType : number = plot:GetResourceType();

    -- TODO: Account for trade/diplomacy resources.
    if eResourceType ~= -1 and Players[pCity:GetOwner()]:GetResources():IsResourceExtractableAt(plot) then
      if kResources[eResourceType] == nil then
        kResources[eResourceType] = 1;
      else
        kResources[eResourceType] = kResources[eResourceType] + 1;
      end
    end
  end
  return kResources;
end

-- ===========================================================================
--	Obtain the yields from the worked plots
-- ===========================================================================
function GetWorkedTileYieldData( pCity:table, pCulture:table )

  -- Loop through all the plots for a given city; tallying the resource amount.
  local kYields : table = {
    YIELD_PRODUCTION= 0,
    YIELD_FOOD		= 0,
    YIELD_GOLD		= 0,
    YIELD_FAITH		= 0,
    YIELD_SCIENCE	= 0,
    YIELD_CULTURE	= 0,
    TOURISM			= 0,
  };
  local cityPlots : table = Map.GetCityPlots():GetPurchasedPlots(pCity);
  local pCitizens	: table = pCity:GetCitizens();	
  for _, plotID in ipairs(cityPlots) do		
    local plot	: table = Map.GetPlotByIndex(plotID);
    local x		: number = plot:GetX();
    local y		: number = plot:GetY();
    isPlotWorked = pCitizens:IsPlotWorked(x,y);
    if isPlotWorked then
      for row in GameInfo.Yields() do			
        kYields[row.YieldType] = kYields[row.YieldType] + plot:GetYield(row.Index);				
      end
    end

    -- Support tourism.
    -- Not a common yield, and only exposure from game core is based off
    -- of the plot so the sum is easily shown, but it's not possible to 
    -- show how individual buildings contribute... yet.
    kYields["TOURISM"] = kYields["TOURISM"] + pCulture:GetTourismAt( plotID );
  end
  return kYields;
end



-- ===========================================================================
--	Set a group to it's proper collapse/open state
--	Set + - in group row
-- ===========================================================================
function RealizeGroup( instance:table )
  local v :number = (instance["isCollapsed"]==false and instance.RowExpandCheck:GetSizeY() or 0);
  instance.RowExpandCheck:SetTextureOffsetVal(0, v);

  instance.ContentStack:CalculateSize();	
  instance.CollapseScroll:CalculateSize();
  
  local groupHeight	:number = instance.ContentStack:GetSizeY();
  instance.CollapseAnim:SetBeginVal(0, -(groupHeight - instance["CollapsePadding"]));
  instance.CollapseScroll:SetSizeY( groupHeight );

  instance.Top:ReprocessAnchoring();
end

-- ===========================================================================
--	Callback
--	Expand or contract a group based on its existing state.
-- ===========================================================================
function OnToggleCollapseGroup( instance:table )
  instance["isCollapsed"] = not instance["isCollapsed"];
  instance.CollapseAnim:Reverse();
  RealizeGroup( instance );
end

-- ===========================================================================
--	Toggle a group expanding / collapsing
--	instance,	A group instance.
-- ===========================================================================
function OnAnimGroupCollapse( instance:table)
    -- Helper
  function lerp(y1:number,y2:number,x:number)
    return y1 + (y2-y1)*x;
  end
  local groupHeight	:number = instance.ContentStack:GetSizeY();
  local collapseHeight:number = instance["CollapsePadding"]~=nil and instance["CollapsePadding"] or 0;
  local startY		:number = instance["isCollapsed"]==true  and groupHeight or collapseHeight;
  local endY			:number = instance["isCollapsed"]==false and groupHeight or collapseHeight;
  local progress		:number = instance.CollapseAnim:GetProgress();
  local sizeY			:number = lerp(startY,endY,progress);
    
  instance.CollapseScroll:SetSizeY( sizeY );	
  instance.ContentStack:ReprocessAnchoring();	
  instance.Top:ReprocessAnchoring()

  Controls.Stack:CalculateSize();
  Controls.Scroll:CalculateSize();			
end


-- ===========================================================================
function SetGroupCollapsePadding( instance:table, amount:number )
  instance["CollapsePadding"] = amount;
end


-- ===========================================================================
function ResetTabForNewPageContent()
  m_uiGroups = {};
  m_simpleIM:ResetInstances();
  m_groupIM:ResetInstances();
  m_isCollapsing = true;
  Controls.CollapseAll:LocalizeAndSetText("LOC_HUD_REPORTS_COLLAPSE_ALL");
  Controls.Scroll:SetScrollValue( 0 );	
end


-- ===========================================================================
--	Instantiate a new collapsable row (group) holder & wire it up.
--	ARGS:	(optional) isCollapsed
--	RETURNS: New group instance
-- ===========================================================================
function NewCollapsibleGroupInstance( isCollapsed:boolean )
  if isCollapsed == nil then
    isCollapsed = false;
  end
  local instance:table = m_groupIM:GetInstance();	
  instance.ContentStack:DestroyAllChildren();
  instance["isCollapsed"]		= isCollapsed;
  instance["CollapsePadding"] = nil;				-- reset any prior collapse padding

  -- CUI
  instance["Children"] = {}
  instance["Descend"] = false
  --
  instance.CollapseAnim:SetToBeginning();
  if isCollapsed == false then
    instance.CollapseAnim:SetToEnd();
  end	

  instance.RowHeaderButton:RegisterCallback( Mouse.eLClick, function() OnToggleCollapseGroup(instance); end );			
    instance.RowHeaderButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

  instance.CollapseAnim:RegisterAnimCallback(               function() OnAnimGroupCollapse( instance ); end );

  table.insert( m_uiGroups, instance );

  return instance;
end


-- ===========================================================================
--	debug - Create a test page.
-- ===========================================================================
function ViewTestPage()

  ResetTabForNewPageContent();

  local instance:table = NewCollapsibleGroupInstance();	
  instance.RowHeaderButton:SetText( "Test City Icon 1" );
  instance.Top:SetID("foo");
  
  local pHeaderInstance:table = {}
  ContextPtr:BuildInstanceForControl( "CityIncomeHeaderInstance", pHeaderInstance, instance.ContentStack ) ;	

  local pCityInstance:table = {};
  ContextPtr:BuildInstanceForControl( "CityIncomeInstance", pCityInstance, instance.ContentStack ) ;

  for i=1,3,1 do
    local pLineItemInstance:table = {};
    ContextPtr:BuildInstanceForControl("CityIncomeLineItemInstance", pLineItemInstance, pCityInstance.LineItemStack );
  end

  local pFooterInstance:table = {};
  ContextPtr:BuildInstanceForControl("CityIncomeFooterInstance", pFooterInstance, instance.ContentStack  );
  
  SetGroupCollapsePadding(instance, pFooterInstance.Top:GetSizeY() );
  RealizeGroup( instance );
  
  Controls.BottomYieldTotals:SetHide( true );
  Controls.BottomResourceTotals:SetHide( true );
  Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - (Controls.BottomYieldTotals:GetSizeY() + SIZE_HEIGHT_PADDING_BOTTOM_ADJUST ) );
end

-- ===========================================================================
--	Tab Callback
-- ===========================================================================
function ViewYieldsPage()	

  ResetTabForNewPageContent();

  local instance:table = nil;
  instance = NewCollapsibleGroupInstance();
  instance.RowHeaderButton:SetText( Locale.Lookup("LOC_HUD_REPORTS_ROW_CITY_INCOME") );
  
  -- CUI
  instance.Amount:SetHide(true);
  instance.AmenitiesContainer:SetHide(true);
  --
  
  local pHeaderInstance:table = {}
  ContextPtr:BuildInstanceForControl( "CityIncomeHeaderInstance", pHeaderInstance, instance.ContentStack ) ;	

  local goldCityTotal		:number = 0;
  local faithCityTotal	:number = 0;
  local scienceCityTotal	:number = 0;
  local cultureCityTotal	:number = 0;
  local tourismCityTotal	:number = 0;
  

  -- ========== City Income ==========

  function CreatLineItemInstance(cityInstance:table, name:string, production:number, gold:number, food:number, science:number, culture:number, faith:number)
    local lineInstance:table = {};
    ContextPtr:BuildInstanceForControl("CityIncomeLineItemInstance", lineInstance, cityInstance.LineItemStack );
    TruncateStringWithTooltipClean(lineInstance.LineItemName, 160, name);
    lineInstance.Production:SetText( toPlusMinusNoneString(production));
    lineInstance.Food:SetText( toPlusMinusNoneString(food));
    lineInstance.Gold:SetText( toPlusMinusNoneString(gold));
    lineInstance.Faith:SetText( toPlusMinusNoneString(faith));
    lineInstance.Science:SetText( toPlusMinusNoneString(science));
    lineInstance.Culture:SetText( toPlusMinusNoneString(culture));

    return lineInstance;
  end

  for cityName,kCityData in pairs(m_kCityData) do
    local pCityInstance:table = {};
    ContextPtr:BuildInstanceForControl( "CityIncomeInstance", pCityInstance, instance.ContentStack ) ;
    -- CUI: move to city
    pCityInstance.MoveToCityButton:SetVoid1(kCityData.City:GetID());
    pCityInstance.MoveToCityButton:RegisterCallback(Mouse.eLClick, CuiRealizeLookAtCity);
    --
    pCityInstance.LineItemStack:DestroyAllChildren();
    TruncateStringWithTooltip(pCityInstance.CityName, 230, Locale.Lookup(kCityData.CityName)); 

    --Great works
    local greatWorks:table = GetGreatWorksForCity(kCityData.City);

    -- Current Production
    local kCurrentProduction:table = kCityData.ProductionQueue[1];
    pCityInstance.CurrentProduction:SetHide( kCurrentProduction == nil );
    if kCurrentProduction ~= nil then
      local tooltip:string = Locale.Lookup(kCurrentProduction.Name);
      if kCurrentProduction.Description ~= nil then
        tooltip = tooltip .. "[NEWLINE]" .. Locale.Lookup(kCurrentProduction.Description);
      end
      pCityInstance.CurrentProduction:SetToolTipString( tooltip )

      --[[ CUI: bug fix, devs forget to change this bit code when they implement production queue
      if kCurrentProduction.Icon then
        pCityInstance.CityBannerBackground:SetHide( false );
        pCityInstance.CurrentProduction:SetIcon( kCurrentProduction.Icon );
        pCityInstance.CityProductionMeter:SetPercent( kCurrentProduction.PercentComplete );
        pCityInstance.CityProductionNextTurn:SetPercent( kCurrentProduction.PercentCompleteNextTurn );			
        pCityInstance.ProductionBorder:SetHide( kCurrentProduction.Type == ProductionType.DISTRICT );
      else
        pCityInstance.CityBannerBackground:SetHide( true );
      end
      ]]
      
      -- CUI: new code
      if kCurrentProduction.Icons then
        local correctIcon:string = "";
        if kCurrentProduction.Icons[5] then
          correctIcon = kCurrentProduction.Icons[5]; -- use last icon for now, because the new icons are broken
        elseif kCurrentProduction.Icons[1] then
          correctIcon = kCurrentProduction.Icons[1];
        end
        pCityInstance.CityBannerBackground:SetHide( false );
        pCityInstance.CurrentProduction:SetIcon( correctIcon );
        pCityInstance.CityProductionMeter:SetPercent( kCurrentProduction.PercentComplete );
        pCityInstance.CityProductionNextTurn:SetPercent( kCurrentProduction.PercentCompleteNextTurn );			
        pCityInstance.ProductionBorder:SetHide( kCurrentProduction.Type == ProductionType.DISTRICT );
      else
        pCityInstance.CityBannerBackground:SetHide( true );
      end
      --
    end

    pCityInstance.Production:SetText( toPlusMinusString(kCityData.ProductionPerTurn) );
    pCityInstance.Food:SetText( toPlusMinusString(CuiGetFoodIncrement(kCityData))); -- CUI
    pCityInstance.Gold:SetText( toPlusMinusString(kCityData.GoldPerTurn) );
    pCityInstance.Faith:SetText( toPlusMinusString(kCityData.FaithPerTurn) );
    pCityInstance.Science:SetText( toPlusMinusString(kCityData.SciencePerTurn) );
    pCityInstance.Culture:SetText( toPlusMinusString(kCityData.CulturePerTurn) );
    pCityInstance.Tourism:SetText( toPlusMinusString(kCityData.WorkedTileYields["TOURISM"]) );

    -- Add to all cities totals
    goldCityTotal	= goldCityTotal + kCityData.GoldPerTurn;
    faithCityTotal	= faithCityTotal + kCityData.FaithPerTurn;
    scienceCityTotal= scienceCityTotal + kCityData.SciencePerTurn;
    cultureCityTotal= cultureCityTotal + kCityData.CulturePerTurn;
    tourismCityTotal= tourismCityTotal + kCityData.WorkedTileYields["TOURISM"];

    -- CUI_START: line items
    if cui_ShowCityDetail then
      for i,kDistrict in ipairs(kCityData.BuildingsAndDistricts) do			
        --District line item
        local districtInstance = CreatLineItemInstance(	pCityInstance, 
                                kDistrict.Name,
                                kDistrict.Production,
                                kDistrict.Gold,
                                kDistrict.Food,
                                kDistrict.Science,
                                kDistrict.Culture,
                                kDistrict.Faith);
        districtInstance.DistrictIcon:SetHide(false);
        districtInstance.DistrictIcon:SetIcon(kDistrict.Icon);

        function HasValidAdjacencyBonus(adjacencyTable:table)
          for _, yield in pairs(adjacencyTable) do
            if yield ~= 0 then
              return true;
            end
          end
          return false;
        end

        --Adjacency
        if HasValidAdjacencyBonus(kDistrict.AdjacencyBonus) then
          CreatLineItemInstance(	pCityInstance,
                      INDENT_STRING .. Locale.Lookup("LOC_HUD_REPORTS_ADJACENCY_BONUS"),
                      kDistrict.AdjacencyBonus.Production,
                      kDistrict.AdjacencyBonus.Gold,
                      kDistrict.AdjacencyBonus.Food,
                      kDistrict.AdjacencyBonus.Science,
                      kDistrict.AdjacencyBonus.Culture,
                      kDistrict.AdjacencyBonus.Faith);
        end

        
        for i,kBuilding in ipairs(kDistrict.Buildings) do
          CreatLineItemInstance(	pCityInstance,
                      INDENT_STRING ..  kBuilding.Name,
                      kBuilding.ProductionPerTurn,
                      kBuilding.GoldPerTurn,
                      kBuilding.FoodPerTurn,
                      kBuilding.SciencePerTurn,
                      kBuilding.CulturePerTurn,
                      kBuilding.FaithPerTurn);

          --Add great works
          if greatWorks[kBuilding.Type] ~= nil then
            --Add our line items!
            for _, kGreatWork in ipairs(greatWorks[kBuilding.Type]) do
              local pLineItemInstance = CreatLineItemInstance(	pCityInstance, INDENT_STRING .. INDENT_STRING ..  Locale.Lookup(kGreatWork.Name), 0, 0, 0,	0, 0, 0);
              for _, yield in ipairs(kGreatWork.YieldChanges) do
                if (yield.YieldType == "YIELD_FOOD") then
                  pLineItemInstance.Food:SetText( toPlusMinusNoneString(yield.YieldChange) );
                elseif (yield.YieldType == "YIELD_PRODUCTION") then
                  pLineItemInstance.Production:SetText( toPlusMinusNoneString(yield.YieldChange) );
                elseif (yield.YieldType == "YIELD_GOLD") then
                  pLineItemInstance.Gold:SetText( toPlusMinusNoneString(yield.YieldChange) );
                elseif (yield.YieldType == "YIELD_SCIENCE") then
                  pLineItemInstance.Science:SetText( toPlusMinusNoneString(yield.YieldChange) );
                elseif (yield.YieldType == "YIELD_CULTURE") then
                  pLineItemInstance.Culture:SetText( toPlusMinusNoneString(yield.YieldChange) );
                elseif (yield.YieldType == "YIELD_FAITH") then
                  pLineItemInstance.Faith:SetText( toPlusMinusNoneString(yield.YieldChange) );
                end
              end
            end
          end

        end
      end

      -- Display wonder yields
      if kCityData.Wonders then
        for _, wonder in ipairs(kCityData.Wonders) do
          if wonder.Yields[1] ~= nil or greatWorks[wonder.Type] ~= nil then
          -- Assign yields to the line item
            local pLineItemInstance:table = CreatLineItemInstance(pCityInstance, wonder.Name, 0, 0, 0, 0, 0, 0);
            for _, yield in ipairs(wonder.Yields) do
              if (yield.YieldType == "YIELD_FOOD") then
                pLineItemInstance.Food:SetText( toPlusMinusNoneString(yield.YieldChange) );
              elseif (yield.YieldType == "YIELD_PRODUCTION") then
                pLineItemInstance.Production:SetText( toPlusMinusNoneString(yield.YieldChange) );
              elseif (yield.YieldType == "YIELD_GOLD") then
                pLineItemInstance.Gold:SetText( toPlusMinusNoneString(yield.YieldChange) );
              elseif (yield.YieldType == "YIELD_SCIENCE") then
                pLineItemInstance.Science:SetText( toPlusMinusNoneString(yield.YieldChange) );
              elseif (yield.YieldType == "YIELD_CULTURE") then
                pLineItemInstance.Culture:SetText( toPlusMinusNoneString(yield.YieldChange) );
              elseif (yield.YieldType == "YIELD_FAITH") then
                pLineItemInstance.Faith:SetText( toPlusMinusNoneString(yield.YieldChange) );
              end
            end
          end

          --Add great works
          if greatWorks[wonder.Type] ~= nil then
            --Add our line items!
            for _, kGreatWork in ipairs(greatWorks[wonder.Type]) do
              local pLineItemInstance = CreatLineItemInstance(	pCityInstance, INDENT_STRING ..  Locale.Lookup(kGreatWork.Name), 0, 0, 0,	0, 0, 0);
              for _, yield in ipairs(kGreatWork.YieldChanges) do
                if (yield.YieldType == "YIELD_FOOD") then
                  pLineItemInstance.Food:SetText( toPlusMinusNoneString(yield.YieldChange) );
                elseif (yield.YieldType == "YIELD_PRODUCTION") then
                  pLineItemInstance.Production:SetText( toPlusMinusNoneString(yield.YieldChange) );
                elseif (yield.YieldType == "YIELD_GOLD") then
                  pLineItemInstance.Gold:SetText( toPlusMinusNoneString(yield.YieldChange) );
                elseif (yield.YieldType == "YIELD_SCIENCE") then
                  pLineItemInstance.Science:SetText( toPlusMinusNoneString(yield.YieldChange) );
                elseif (yield.YieldType == "YIELD_CULTURE") then
                  pLineItemInstance.Culture:SetText( toPlusMinusNoneString(yield.YieldChange) );
                elseif (yield.YieldType == "YIELD_FAITH") then
                  pLineItemInstance.Faith:SetText( toPlusMinusNoneString(yield.YieldChange) );
                end
              end
            end
          end
        end
      end

      -- Display route yields
      if kCityData.OutgoingRoutes then
        for i,route in ipairs(kCityData.OutgoingRoutes) do
          if route ~= nil then
            if route.OriginYields then
              -- Find destination city
              local pDestPlayer:table = Players[route.DestinationCityPlayer];
              local pDestPlayerCities:table = pDestPlayer:GetCities();
              local pDestCity:table = pDestPlayerCities:FindID(route.DestinationCityID);

              --Assign yields to the line item
              local pLineItemInstance:table = CreatLineItemInstance(pCityInstance, Locale.Lookup("LOC_HUD_REPORTS_TRADE_WITH", Locale.Lookup(pDestCity:GetName())), 0, 0, 0, 0, 0, 0);
              for j,yield in ipairs(route.OriginYields) do
                local yieldInfo = GameInfo.Yields[yield.YieldIndex];
                if yieldInfo then
                  if (yieldInfo.YieldType == "YIELD_FOOD") then
                    pLineItemInstance.Food:SetText( toPlusMinusNoneString(yield.Amount) );
                  elseif (yieldInfo.YieldType == "YIELD_PRODUCTION") then
                    pLineItemInstance.Production:SetText( toPlusMinusNoneString(yield.Amount) );
                  elseif (yieldInfo.YieldType == "YIELD_GOLD") then
                    pLineItemInstance.Gold:SetText( toPlusMinusNoneString(yield.Amount) );
                  elseif (yieldInfo.YieldType == "YIELD_SCIENCE") then
                    pLineItemInstance.Science:SetText( toPlusMinusNoneString(yield.Amount) );
                  elseif (yieldInfo.YieldType == "YIELD_CULTURE") then
                    pLineItemInstance.Culture:SetText( toPlusMinusNoneString(yield.Amount) );
                  elseif (yieldInfo.YieldType == "YIELD_FAITH") then
                    pLineItemInstance.Faith:SetText( toPlusMinusNoneString(yield.Amount) );
                  end
                end
              end
            end
          end
        end
      end

      --Worked Tiles
      CreatLineItemInstance(	pCityInstance,
                  Locale.Lookup("LOC_HUD_REPORTS_WORKED_TILES"),
                  kCityData.WorkedTileYields["YIELD_PRODUCTION"],
                  kCityData.WorkedTileYields["YIELD_GOLD"],
                  kCityData.WorkedTileYields["YIELD_FOOD"],
                  kCityData.WorkedTileYields["YIELD_SCIENCE"],
                  kCityData.WorkedTileYields["YIELD_CULTURE"],
                  kCityData.WorkedTileYields["YIELD_FAITH"]);

      local iYieldPercent = (Round(1 + (kCityData.HappinessNonFoodYieldModifier/100), 2)*.1);
      CreatLineItemInstance(	pCityInstance,
                  Locale.Lookup("LOC_HUD_REPORTS_HEADER_AMENITIES"),
                  kCityData.WorkedTileYields["YIELD_PRODUCTION"] * iYieldPercent,
                  kCityData.WorkedTileYields["YIELD_GOLD"] * iYieldPercent,
                  0,
                  kCityData.WorkedTileYields["YIELD_SCIENCE"] * iYieldPercent,
                  kCityData.WorkedTileYields["YIELD_CULTURE"] * iYieldPercent,
                  kCityData.WorkedTileYields["YIELD_FAITH"] * iYieldPercent);

      local populationToCultureScale:number = GameInfo.GlobalParameters["CULTURE_PERCENTAGE_YIELD_PER_POP"].Value / 100;
      CreatLineItemInstance(	pCityInstance,
                  Locale.Lookup("LOC_HUD_CITY_POPULATION"),
                  0,
                  0,
                  -(kCityData.FoodPerTurn - kCityData.FoodSurplus), -- CUI: food consumption
                  0,
                  kCityData["Population"] * populationToCultureScale, 
                  0);

      pCityInstance.LineItemStack:CalculateSize();
      pCityInstance.Darken:SetSizeY( pCityInstance.LineItemStack:GetSizeY() + DARKEN_CITY_INCOME_AREA_ADDITIONAL_Y );
      pCityInstance.Top:ReprocessAnchoring();
    end
    -- CUI_END
  end

  local pFooterInstance:table = {};
  ContextPtr:BuildInstanceForControl("CityIncomeFooterInstance", pFooterInstance, instance.ContentStack  );
  pFooterInstance.Gold:SetText( "[Icon_GOLD]"..toPlusMinusString(goldCityTotal) );
  pFooterInstance.Faith:SetText( "[Icon_FAITH]"..toPlusMinusString(faithCityTotal) );
  pFooterInstance.Science:SetText( "[Icon_SCIENCE]"..toPlusMinusString(scienceCityTotal) );
  pFooterInstance.Culture:SetText( "[Icon_CULTURE]"..toPlusMinusString(cultureCityTotal) );
  pFooterInstance.Tourism:SetText( "[Icon_TOURISM]"..toPlusMinusString(tourismCityTotal) );

  SetGroupCollapsePadding(instance, pFooterInstance.Top:GetSizeY() );
  RealizeGroup( instance );


  -- ========== Building Expenses ==========

  instance = NewCollapsibleGroupInstance();
  instance.RowHeaderButton:SetText( Locale.Lookup("LOC_HUD_REPORTS_ROW_BUILDING_EXPENSES") );

  -- CUI
  instance.Amount:SetHide(true);
  instance.AmenitiesContainer:SetHide(true);
  --
  local pHeader:table = {};
  ContextPtr:BuildInstanceForControl( "BuildingExpensesHeaderInstance", pHeader, instance.ContentStack ) ;

  local iTotalBuildingMaintenance :number = 0;
  -- CUI_START
  local cui_BDList:table = {};
  for cityName,kCityData in pairs(m_kCityData) do

    --[[ old building maintenance
    for _,kBuilding in ipairs(kCityData.Buildings) do
      if (kBuilding.Maintenance > 0 and kBuilding.isPillaged == false) then
        local pBuildingInstance:table = {};		
        ContextPtr:BuildInstanceForControl( "BuildingExpensesEntryInstance", pBuildingInstance, instance.ContentStack ) ;		
        TruncateStringWithTooltip(pBuildingInstance.CityName, 224, Locale.Lookup(cityName)); 
        pBuildingInstance.BuildingName:SetText( Locale.Lookup(kBuilding.Name) );
        pBuildingInstance.Gold:SetText( "-"..tostring(kBuilding.Maintenance));
        iTotalBuildingMaintenance = iTotalBuildingMaintenance - kBuilding.Maintenance;
      end
    end
    for _,kDistrict in ipairs(kCityData.BuildingsAndDistricts) do
      if (kDistrict.Maintenance > 0 and kDistrict.isPillaged == false) then
        local pDistrictInstance:table = {};		
        ContextPtr:BuildInstanceForControl( "BuildingExpensesEntryInstance", pDistrictInstance, instance.ContentStack ) ;		
        TruncateStringWithTooltip(pDistrictInstance.CityName, 224, Locale.Lookup(cityName)); 
        pDistrictInstance.BuildingName:SetText( Locale.Lookup(kDistrict.Name) );
        pDistrictInstance.Gold:SetText( "-"..tostring(kDistrict.Maintenance));
        iTotalBuildingMaintenance = iTotalBuildingMaintenance - kDistrict.Maintenance;
      end
    end
    ]]

    -- new building maintenance
    for _,kDistrict in ipairs(kCityData.BuildingsAndDistricts) do
      if (kDistrict.Maintenance > 0 and kDistrict.isPillaged == false) then
        if cui_BDList[kDistrict.Name] == nil then
          cui_BDList[kDistrict.Name] = {1, -kDistrict.Maintenance};
        else
          cui_BDList[kDistrict.Name][1] = cui_BDList[kDistrict.Name][1] + 1;
          cui_BDList[kDistrict.Name][2] = cui_BDList[kDistrict.Name][2] - kDistrict.Maintenance;
        end
        iTotalBuildingMaintenance = iTotalBuildingMaintenance - kDistrict.Maintenance;
      end
    end
    
    for _,kBuilding in ipairs(kCityData.Buildings) do
      if (kBuilding.Maintenance > 0 and kBuilding.isPillaged == false) then
        if cui_BDList[kBuilding.Name] == nil then
          cui_BDList[kBuilding.Name] = {1, -kBuilding.Maintenance};
        else
          cui_BDList[kBuilding.Name][1] = cui_BDList[kBuilding.Name][1] + 1;
          cui_BDList[kBuilding.Name][2] = cui_BDList[kBuilding.Name][2] - kBuilding.Maintenance;
        end
        iTotalBuildingMaintenance = iTotalBuildingMaintenance - kBuilding.Maintenance;
      end
    end
  end

  for name, info in pairs(cui_BDList) do
    local pBuildingInstance:table = {};
    ContextPtr:BuildInstanceForControl("BuildingExpensesEntryInstance", pBuildingInstance, instance.ContentStack);
    TruncateStringWithTooltip(pBuildingInstance.BuildingName, 224, Locale.Lookup(name));
    pBuildingInstance.BuildingNum:SetText(info[1]);
    pBuildingInstance.Gold:SetText(info[2]);
  end
  -- CUI_END
  
  local pBuildingFooterInstance:table = {};		
  ContextPtr:BuildInstanceForControl( "GoldFooterInstance", pBuildingFooterInstance, instance.ContentStack ) ;		
  pBuildingFooterInstance.Gold:SetText("[ICON_Gold]"..tostring(iTotalBuildingMaintenance) );

  SetGroupCollapsePadding(instance, pBuildingFooterInstance.Top:GetSizeY() );
  RealizeGroup( instance );

  -- ========== Unit Expenses ==========

  if GameCapabilities.HasCapability("CAPABILITY_REPORTS_UNIT_EXPENSES") then 
    instance = NewCollapsibleGroupInstance();
    instance.RowHeaderButton:SetText( Locale.Lookup("LOC_HUD_REPORTS_ROW_UNIT_EXPENSES") );

    -- CUI
    instance.Amount:SetHide(true);
    instance.AmenitiesContainer:SetHide(true);
    --
    
    -- Header
    local pHeader:table = {};
    ContextPtr:BuildInstanceForControl( "UnitExpensesHeaderInstance", pHeader, instance.ContentStack ) ;

    -- Units
    local iTotalUnitMaintenance:number = 0;
    for UnitType,kUnitData in pairs(m_kUnitData) do
      local pUnitInstance:table = {};
      ContextPtr:BuildInstanceForControl( "UnitExpensesEntryInstance", pUnitInstance, instance.ContentStack );
      pUnitInstance.UnitName:SetText(Locale.Lookup( kUnitData.Name ));
      pUnitInstance.UnitCount:SetText(kUnitData.Count);
      pUnitInstance.Gold:SetText("-" .. kUnitData.Maintenance);
      iTotalUnitMaintenance = iTotalUnitMaintenance - kUnitData.Maintenance;
    end

    -- Footer
    local pUnitFooterInstance:table = {};		
    ContextPtr:BuildInstanceForControl( "GoldFooterInstance", pUnitFooterInstance, instance.ContentStack ) ;		
    pUnitFooterInstance.Gold:SetText("[ICON_Gold]"..tostring(iTotalUnitMaintenance) );

    SetGroupCollapsePadding(instance, pUnitFooterInstance.Top:GetSizeY() );
    RealizeGroup( instance );
  end

  -- ========== Diplomatic Deals Expenses ==========
  
  if GameCapabilities.HasCapability("CAPABILITY_REPORTS_DIPLOMATIC_DEALS") then 
    instance = NewCollapsibleGroupInstance();	
    instance.RowHeaderButton:SetText( Locale.Lookup("LOC_HUD_REPORTS_ROW_DIPLOMATIC_DEALS") );

    -- CUI
    instance.Amount:SetHide(true);
    instance.AmenitiesContainer:SetHide(true);
    --
    
    local pHeader:table = {};
    ContextPtr:BuildInstanceForControl( "DealHeaderInstance", pHeader, instance.ContentStack ) ;

    local iTotalDealGold :number = 0;
    for i,kDeal in ipairs(m_kDealData) do
      if kDeal.Type == DealItemTypes.GOLD then
        local pDealInstance:table = {};		
        ContextPtr:BuildInstanceForControl( "DealEntryInstance", pDealInstance, instance.ContentStack ) ;		

        pDealInstance.Civilization:SetText( kDeal.Name );
        pDealInstance.Duration:SetText( kDeal.Duration );
        if kDeal.IsOutgoing then
          pDealInstance.Gold:SetText( "-"..tostring(kDeal.Amount) );
          iTotalDealGold = iTotalDealGold - kDeal.Amount;
        else
          pDealInstance.Gold:SetText( "+"..tostring(kDeal.Amount) );
          iTotalDealGold = iTotalDealGold + kDeal.Amount;
        end
      end
    end
    local pDealFooterInstance:table = {};		
    ContextPtr:BuildInstanceForControl( "GoldFooterInstance", pDealFooterInstance, instance.ContentStack ) ;		
    pDealFooterInstance.Gold:SetText("[ICON_Gold]"..tostring(iTotalDealGold) );

    SetGroupCollapsePadding(instance, pDealFooterInstance.Top:GetSizeY() );
    RealizeGroup( instance );
  end


  -- ========== TOTALS ==========

  Controls.Stack:CalculateSize();
  Controls.Scroll:CalculateSize();

  -- Totals at the bottom [Definitive values]
  local localPlayer = Players[Game.GetLocalPlayer()];
  --Gold
  local playerTreasury:table	= localPlayer:GetTreasury();
  Controls.GoldIncome:SetText( toPlusMinusNoneString( playerTreasury:GetGoldYield() ));
  Controls.GoldExpense:SetText( toPlusMinusNoneString( -playerTreasury:GetTotalMaintenance() ));	-- Flip that value!
  Controls.GoldNet:SetText( toPlusMinusNoneString( playerTreasury:GetGoldYield() - playerTreasury:GetTotalMaintenance() ));
  Controls.GoldBalance:SetText( m_kCityTotalData.Treasury[YieldTypes.GOLD] );

  
  --Faith
  local playerReligion:table	= localPlayer:GetReligion();
  Controls.FaithIncome:SetText( toPlusMinusNoneString(playerReligion:GetFaithYield()));
  Controls.FaithNet:SetText( toPlusMinusNoneString(playerReligion:GetFaithYield()));
  Controls.FaithBalance:SetText( m_kCityTotalData.Treasury[YieldTypes.FAITH] );

  --Science
  local playerTechnology:table	= localPlayer:GetTechs();
  Controls.ScienceIncome:SetText( toPlusMinusNoneString(playerTechnology:GetScienceYield()));
  Controls.ScienceBalance:SetText( m_kCityTotalData.Treasury[YieldTypes.SCIENCE] );
  
  --Culture
  local playerCulture:table	= localPlayer:GetCulture();
  Controls.CultureIncome:SetText(toPlusMinusNoneString(playerCulture:GetCultureYield()));
  Controls.CultureBalance:SetText(m_kCityTotalData.Treasury[YieldTypes.CULTURE] );
  
  --Tourism. We don't talk about this one much.
  Controls.TourismIncome:SetText( toPlusMinusNoneString( m_kCityTotalData.Income["TOURISM"] ));	
  Controls.TourismBalance:SetText( m_kCityTotalData.Treasury["TOURISM"] );
  
  Controls.CollapseAll:SetHide(false);
  Controls.BottomYieldTotals:SetHide( false );
  Controls.BottomYieldTotals:SetSizeY( SIZE_HEIGHT_BOTTOM_YIELDS );
  Controls.BottomResourceTotals:SetHide( true );
  Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - (Controls.BottomYieldTotals:GetSizeY() + SIZE_HEIGHT_PADDING_BOTTOM_ADJUST ) );	
end


-- ===========================================================================
--	Tab Callback
-- ===========================================================================
function ViewResourcesPage()	

  ResetTabForNewPageContent();
  local strategicResources:string = "";
  local luxuryResources	:string = "";
  local kBonuses			:table	= {};
  local kLuxuries			:table	= {};
  local kStrategics		:table	= {};
  
  -- CUI: sort resources
  for eResourceType,kSingleResourceData in CuiSortedTable(m_kResourceData, CuiCmpResource) do
    -- CUI: filter
    
    if (cui_ShowStrategic and kSingleResourceData.IsStrategic) or
       (cui_ShowLuxury    and kSingleResourceData.IsLuxury) or
       (cui_ShowBonus     and kSingleResourceData.IsBonus) then
    local instance:table = NewCollapsibleGroupInstance();	

    local kResource :table = GameInfo.Resources[eResourceType];
    instance.RowHeaderButton:SetText(  kSingleResourceData.Icon..Locale.Lookup( kResource.Name ) );

    local pHeaderInstance:table = {};
    ContextPtr:BuildInstanceForControl( "ResourcesHeaderInstance", pHeaderInstance, instance.ContentStack ) ;

    local kResourceEntries:table = kSingleResourceData.EntryList;
    for i,kEntry in ipairs(kResourceEntries) do
      local pEntryInstance:table = {};
      ContextPtr:BuildInstanceForControl( "ResourcesEntryInstance", pEntryInstance, instance.ContentStack ) ;
      pEntryInstance.CityName:SetText( Locale.Lookup(kEntry.EntryText) );
      pEntryInstance.Control:SetText( Locale.Lookup(kEntry.ControlText) );
      pEntryInstance.Amount:SetText( (kEntry.Amount<=0) and tostring(kEntry.Amount) or "+"..tostring(kEntry.Amount) );
    end

    --[[ CUI_START: remove footer, move amount to header
    local pFooterInstance:table = {};
    ContextPtr:BuildInstanceForControl( "ResourcesFooterInstance", pFooterInstance, instance.ContentStack ) ;
    pFooterInstance.Amount:SetText( tostring(kSingleResourceData.Total) );		
    ]]
    instance.Amount:SetHide(false);
    instance.Amount:SetText(Locale.Lookup("LOC_CUI_RS_TOTALS", kSingleResourceData.Total));
      

    -- Show how many of this resource are being allocated to what cities
    local localPlayerID = Game.GetLocalPlayer();
    local localPlayer = Players[localPlayerID];
    local citiesProvidedTo: table = localPlayer:GetResources():GetResourceAllocationCities(GameInfo.Resources[kResource.ResourceType].Index);
    local numCitiesProvidingTo: number = table.count(citiesProvidedTo);

      -- CUI: move amenities to header
      if (numCitiesProvidingTo > 0) then
        instance.AmenitiesContainer:SetHide(false);
        instance.Amenities:SetText("[ICON_Amenities][ICON_GoingTo]"..numCitiesProvidingTo.." "..Locale.Lookup("LOC_PEDIA_CONCEPTS_PAGEGROUP_CITIES_NAME"));
        local amenitiesTooltip: string = "";
        local playerCities = localPlayer:GetCities();
        for i,city in ipairs(citiesProvidedTo) do
          local cityName = Locale.Lookup(playerCities:FindID(city.CityID):GetName());
          if i ~=1 then
            amenitiesTooltip = amenitiesTooltip.. "[NEWLINE]";
          end
          amenitiesTooltip = amenitiesTooltip.. city.AllocationAmount.." [ICON_".. kResource.ResourceType.."] [Icon_GoingTo] " ..cityName;
        end
        instance.Amenities:SetToolTipString(amenitiesTooltip);
      else
        instance.AmenitiesContainer:SetHide(true);
      end

      SetGroupCollapsePadding(instance, 0); -- CUI
      RealizeGroup( instance );
    end
    -- CUI_END

    if kSingleResourceData.IsStrategic then
      table.insert(kStrategics, kSingleResourceData.Icon .. tostring( kSingleResourceData.Total ) );
    elseif kSingleResourceData.IsLuxury then			
      table.insert(kLuxuries, kSingleResourceData.Icon .. tostring( kSingleResourceData.Total ) );
    else
      table.insert(kBonuses, kSingleResourceData.Icon .. tostring( kSingleResourceData.Total ) );
    end
    
  end
  
  m_strategicResourcesIM:ResetInstances();
  for i,v in ipairs(kStrategics) do
    local resourceInstance:table = m_strategicResourcesIM:GetInstance();	
    resourceInstance.Info:SetText( v .. "  " ); -- CUI
  end
  Controls.StrategicResources:CalculateSize();
  Controls.StrategicGrid:ReprocessAnchoring();

  m_bonusResourcesIM:ResetInstances();
  for i,v in ipairs(kBonuses) do
    local resourceInstance:table = m_bonusResourcesIM:GetInstance();	
    resourceInstance.Info:SetText( v .. "  " ); -- CUI
  end
  Controls.BonusResources:CalculateSize();
  Controls.BonusGrid:ReprocessAnchoring();

  m_luxuryResourcesIM:ResetInstances();
  for i,v in ipairs(kLuxuries) do
    local resourceInstance:table = m_luxuryResourcesIM:GetInstance();	
    resourceInstance.Info:SetText( v .. "  " ); -- CUI
  end
  
  Controls.LuxuryResources:CalculateSize();
  Controls.LuxuryResources:ReprocessAnchoring();
  Controls.LuxuryGrid:ReprocessAnchoring();
  
  Controls.Stack:CalculateSize();
  Controls.Scroll:CalculateSize();

  Controls.CollapseAll:SetHide(false);
  Controls.BottomYieldTotals:SetHide( true );
  Controls.BottomResourceTotals:SetHide( false );
  Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - (Controls.BottomResourceTotals:GetSizeY() + SIZE_HEIGHT_PADDING_BOTTOM_ADJUST ) );	
  CuiCollapseAll(); -- CUI: auto collapse, no animation
end

-- ===========================================================================
--	Tab Callback
-- ===========================================================================
function ViewCityStatusPage()

  ResetTabForNewPageContent();

  local instance:table = m_simpleIM:GetInstance();	
  instance.Top:DestroyAllChildren();
  
  local pHeaderInstance:table = {}
  ContextPtr:BuildInstanceForControl( "CityStatusHeaderInstance", pHeaderInstance, instance.Top ) ;	

  -- 
  for cityName, kCityData in CuiSortedTable(m_kCityData, function(t, a, b) return t[a].CityName < t[b].CityName; end) do

    local pCityInstance:table = {}
    ContextPtr:BuildInstanceForControl( "CityStatusEntryInstance", pCityInstance, instance.Top ) ;

    -- CUI_START: city status	
    -- CUI: move to city
    pCityInstance.MoveToCityButton:SetVoid1(kCityData.City:GetID());
    pCityInstance.MoveToCityButton:RegisterCallback(Mouse.eLClick, CuiRealizeLookAtCity);

    -- religion
    local eCityReligion:number = kCityData.City:GetReligion():GetMajorityReligion();
    local eCityPantheon:number = kCityData.City:GetReligion():GetActivePantheon();

    if eCityReligion > 0 then
      local iconName:string = "ICON_" .. GameInfo.Religions[eCityReligion].ReligionType;
      local majorityReligionColor:number = UI.GetColorValue(GameInfo.Religions[eCityReligion].Color);
      if (majorityReligionColor ~= nil) then
        pCityInstance.ReligionIcon:SetColor(majorityReligionColor);
      end
      local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconName,22);
      if (textureOffsetX ~= nil) then
        pCityInstance.ReligionIcon:SetTexture( textureOffsetX, textureOffsetY, textureSheet );
        pCityInstance.ReligionIcon:SetToolTipString(Game.GetReligion():GetName(eCityReligion));
      end
      pCityInstance.ReligionIcon:SetHide(false);

    elseif eCityPantheon >= 0 then
      local iconName:string = "ICON_" .. GameInfo.Religions[0].ReligionType;
      local majorityReligionColor:number = UI.GetColorValue(GameInfo.Religions.RELIGION_PANTHEON.Color);
      if (majorityReligionColor ~= nil) then
        pCityInstance.ReligionIcon:SetColor(majorityReligionColor);
      end
      local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconName,22);
      if (textureOffsetX ~= nil) then
        pCityInstance.ReligionIcon:SetTexture( textureOffsetX, textureOffsetY, textureSheet );
        pCityInstance.ReligionIcon:SetToolTipString(Locale.Lookup("LOC_HUD_CITY_PANTHEON_TT", GameInfo.Beliefs[eCityPantheon].Name));
      end
      pCityInstance.ReligionIcon:SetHide(false);

    else
      pCityInstance.ReligionIcon:SetToolTipString("");
      pCityInstance.ReligionIcon:SetHide(true);
    end

    -- city name
    local sCityName = kCityData.City:IsCapital() and "[ICON_Capital]" or "";
    sCityName = sCityName .. Locale.Lookup(kCityData.CityName);
    TruncateStringWithTooltip(pCityInstance.CityName, 240, sCityName);

    -- population
    if kCityData.HousingMultiplier == 0 or kCityData.Occupied then
      pCityInstance.Population:SetText("[COLOR: 200,62,52,255]" .. tostring(kCityData.Population) .. "[ENDCOLOR]");
      pCityInstance.Population:SetToolTipString(Locale.Lookup("LOC_HUD_CITY_POPULATION_GROWTH_HALTED"));
    elseif kCityData.HousingMultiplier <= 0.5 then
      local iPercent = (1 - kCityData.HousingMultiplier) * 100;
      pCityInstance.Population:SetText("[COLOR: 200,146,52,255]" .. tostring(kCityData.Population) .. "[ENDCOLOR]");
      pCityInstance.Population:SetToolTipString(Locale.Lookup("LOC_HUD_CITY_POPULATION_GROWTH_SLOWED", iPercent));
    else
      pCityInstance.Population:SetText( tostring(kCityData.Population) );
      pCityInstance.Population:SetToolTipString(Locale.Lookup("LOC_HUD_CITY_POPULATION_GROWTH_NORMAL"));
    end

    -- housing
    pCityInstance.Housing:SetText( CuiRedGreenNumber(kCityData.Housing - kCityData.Population) );

    -- amenities
    pCityInstance.Amenities:SetText( CuiRedGreenNumber(kCityData.AmenitiesNum - kCityData.AmenitiesRequiredNum) );

    -- defense
    pCityInstance.Defense:SetText( tostring(kCityData.Defense) );

    -- damage
    if kCityData.GarrisonUnitIcon then
      pCityInstance.GarrisonUnit:SetIcon( kCityData.GarrisonUnitIcon );
      pCityInstance.GarrisonUnit:SetToolTipString( kCityData.GarrisonUnitName );
    else
      pCityInstance.GarrisonUnit:SetIcon("");
      pCityInstance.GarrisonUnit:SetToolTipString("");
    end

    -- trade routes
    local sRoutes:string = #kCityData.OutgoingRoutes > 0 and tostring(#kCityData.OutgoingRoutes) or "-";
    pCityInstance.TradeRoutes:SetText( sRoutes );

    -- districts
    pCityInstance.Districts:SetText( GetDistrictsForCity(kCityData) );
  end

  Controls.Stack:CalculateSize();
  Controls.Scroll:CalculateSize();

  Controls.CollapseAll:SetHide(true);
  Controls.BottomYieldTotals:SetHide( true );
  Controls.BottomResourceTotals:SetHide( true );
  Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - 88);
end
-- ===========================================================================
--	Tab Callback
-- ===========================================================================
function ViewDealsPage()

  ResetTabForNewPageContent();

  for j, pDeal in CuiSortedTable(cui_CurrentDeals, function( t, a, b ) return t[b].EndTurn > t[a].EndTurn; end) do
    local iNumTurns:number = pDeal.EndTurn - Game.GetCurrentGameTurn();
    local instance :table  = NewCollapsibleGroupInstance()

    instance.RowHeaderButton:SetText( Locale.Lookup("LOC_HUD_REPORTS_TRADE_DEAL_WITH")..pDeal.WithCivilization );
    instance.Amount:SetText( Locale.Lookup("LOC_ESPIONAGEPOPUP_TURNS_REMAINING", iNumTurns) .. " ("..tostring(pDeal.EndTurn)..")" );
    instance.Amount:SetHide( false );
    instance.AmenitiesContainer:SetHide(true); -- CUI

    local dealHeaderInstance : table = {}
    ContextPtr:BuildInstanceForControl( "DealsHeader", dealHeaderInstance, instance.ContentStack )

    local iSlots = #pDeal.Sending

    if iSlots < #pDeal.Receiving then iSlots = #pDeal.Receiving end

    for i = 1, iSlots do
      local dealInstance:table = {}
      ContextPtr:BuildInstanceForControl( "DealsInstance", dealInstance, instance.ContentStack )
      table.insert( instance.Children, dealInstance )
    end

    for i, pDealItem in pairs( pDeal.Sending ) do
      if pDealItem.Icon then
        instance.Children[i].Outgoing:SetText( pDealItem.Icon .. " " .. pDealItem.Name )
      else
        instance.Children[i].Outgoing:SetText( pDealItem.Name )
      end
    end

    for i, pDealItem in pairs( pDeal.Receiving ) do
      if pDealItem.Icon then
        instance.Children[i].Incoming:SetText( pDealItem.Icon .. " " .. pDealItem.Name )
      else
        instance.Children[i].Incoming:SetText( pDealItem.Name )
      end
    end

    local pFooterInstance:table = {}
    ContextPtr:BuildInstanceForControl( "DealsFooterInstance", pFooterInstance, instance.ContentStack )
    pFooterInstance.Outgoing:SetText( Locale.Lookup("LOC_HUD_REPORTS_TOTALS")..#pDeal.Sending )
    pFooterInstance.Incoming:SetText( Locale.Lookup("LOC_HUD_REPORTS_TOTALS")..#pDeal.Receiving )

    SetGroupCollapsePadding( instance, pFooterInstance.Top:GetSizeY() )
    RealizeGroup( instance );
  end

  Controls.Stack:CalculateSize();
  Controls.Scroll:CalculateSize();

  Controls.CollapseAll:SetHide( false );
  Controls.BottomYieldTotals:SetHide( true );
  Controls.BottomResourceTotals:SetHide( true );
  Controls.Scroll:SetSizeY( Controls.Main:GetSizeY() - 88);

  CuiCollapseAll(); -- CUI: auto collapse, no animation
  
end

-- ===========================================================================
--
-- ===========================================================================
function AddTabSection( name:string, populateCallback:ifunction )
  local kTab		:table				= m_tabIM:GetInstance();	
  kTab.Button[DATA_FIELD_SELECTION]	= kTab.Selection;

  local callback	:ifunction	= function()
    if m_tabs.prevSelectedControl ~= nil then
      m_tabs.prevSelectedControl[DATA_FIELD_SELECTION]:SetHide(true);
    end
    kTab.Selection:SetHide(false);
    populateCallback();
  end

  kTab.Button:GetTextControl():SetText( Locale.Lookup(name) );
  kTab.Button:SetSizeToText( 40, 20 );
    kTab.Button:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

  m_tabs.AddTab( kTab.Button, callback );
end


-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
  local uiMsg :number = pInputStruct:GetMessageType();
  if uiMsg == KeyEvents.KeyUp then 
    local uiKey = pInputStruct:GetKey();
    if uiKey == Keys.VK_ESCAPE then
      if ContextPtr:IsHidden()==false then
        Close();
        return true;
      end
    end		
  end
  return false;
end


-- ===========================================================================
function Resize()
  local topPanelSizeY:number = 30;

  x,y = UIManager:GetScreenSizeVal();
  Controls.Main:SetSizeY( y - topPanelSizeY );
  Controls.Main:SetOffsetY( topPanelSizeY * 0.5 );
end

-- ===========================================================================
--	Game Event Callback
-- ===========================================================================
function OnLocalPlayerTurnEnd()
  if(GameConfiguration.IsHotseat()) then
    OnCloseButton();
  end
end

-- ===========================================================================
function LateInitialize()
  Resize();	

  m_tabs = CreateTabs( Controls.TabContainer, 42, 34, 0xFF331D05 );
  --AddTabSection( "Test",								ViewTestPage );			--TRONSTER debug
  --AddTabSection( "Test2",								ViewTestPage );			--TRONSTER debug
  AddTabSection( "LOC_HUD_REPORTS_TAB_YIELDS",		ViewYieldsPage );
  AddTabSection( "LOC_HUD_REPORTS_TAB_RESOURCES",		ViewResourcesPage );
  AddTabSection( "LOC_HUD_REPORTS_TAB_CITY_STATUS",	ViewCityStatusPage );

  -- CUI
  AddTabSection( "LOC_HUD_REPORTS_ROW_DIPLOMATIC_DEALS", ViewDealsPage );
  m_tabs.SameSizedTabs(40);
  m_tabs.CenterAlignTabs(-10);
  --
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnInit( isReload:boolean )
  LateInitialize();
  if isReload then		
    if ContextPtr:IsHidden()==false then
      Open();
    end
  end
  m_tabs.AddAnimDeco(Controls.TabAnim, Controls.TabArrow);
end

-- CUI =======================================================================
function CuiRealizeLookAtCity(cityID)
  local city = Players[Game.GetLocalPlayer()]:GetCities():FindID(cityID);
  local locX:number = city:GetX();
  local locY:number = city:GetY();
  UI.LookAtPlotScreenPosition( locX, locY, 0.5, 0.5 );
  UI.SelectCity(city);
  Close();
end

-- CUI =======================================================================
function CuiOnToggleCityDetails()
  cui_ShowCityDetail = not Controls.CuiShowCityDetails:IsSelected();
  CuiSettings:SetBoolean(CuiSettings.SHOW_CITY_DETAILS, cui_ShowCityDetail);
  Controls.CuiShowCityDetails:SetSelected(cui_ShowCityDetail);
  ViewYieldsPage();
end

-- CUI =======================================================================
function CuiOnToggleStrategic()
  cui_ShowStrategic = not Controls.CuiShowStrategic:IsSelected();
  CuiSettings:SetBoolean(CuiSettings.SHOW_STRATEGIC, cui_ShowStrategic);
  Controls.CuiShowStrategic:SetSelected(cui_ShowStrategic);
  ViewResourcesPage();
end

-- CUI =======================================================================
function CuiOnToggleLuxury()
  cui_ShowLuxury = not Controls.CuiShowLuxury:IsSelected();
  CuiSettings:SetBoolean(CuiSettings.SHOW_LUXURY, cui_ShowLuxury);
  Controls.CuiShowLuxury:SetSelected(cui_ShowLuxury);
  ViewResourcesPage();
end

-- CUI =======================================================================
function CuiOnToggleBonus()
  cui_ShowBonus = not Controls.CuiShowBonus:IsSelected();
  CuiSettings:SetBoolean(CuiSettings.SHOW_BONUS, cui_ShowBonus);
  Controls.CuiShowBonus:SetSelected(cui_ShowBonus);
  ViewResourcesPage();
end

-- CUI =======================================================================
function CuiCollapseAll()
  if m_uiGroups == nil or table.count(m_uiGroups) == 0 then
    return;
  end

  for i,instance in ipairs( m_uiGroups ) do
    if instance["isCollapsed"] ~= m_isCollapsing then
      instance["isCollapsed"] = m_isCollapsing;
      instance.CollapseAnim:Reverse();
      instance.CollapseAnim:SetProgress(1);
      RealizeGroup( instance );
    end
  end
  Controls.CollapseAll:LocalizeAndSetText(m_isCollapsing and "LOC_HUD_REPORTS_EXPAND_ALL" or "LOC_HUD_REPORTS_COLLAPSE_ALL");
  m_isCollapsing = not m_isCollapsing;
end

-- CUI =======================================================================
function CuiInit()
  cui_ShowCityDetail = CuiSettings:GetBoolean(CuiSettings.SHOW_CITY_DETAILS);
  Controls.CuiShowCityDetails:RegisterCallback( Mouse.eLClick, CuiOnToggleCityDetails );
  Controls.CuiShowCityDetails:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end )
  Controls.CuiShowCityDetails:SetSelected(cui_ShowCityDetail);

  cui_ShowStrategic = CuiSettings:GetBoolean(CuiSettings.SHOW_STRATEGIC);
  Controls.CuiShowStrategic:RegisterCallback( Mouse.eLClick, CuiOnToggleStrategic );
  Controls.CuiShowStrategic:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end )
  Controls.CuiShowStrategic:SetSelected(cui_ShowStrategic);

  cui_ShowLuxury = CuiSettings:GetBoolean(CuiSettings.SHOW_LUXURY);
  Controls.CuiShowLuxury:RegisterCallback( Mouse.eLClick, CuiOnToggleLuxury );
  Controls.CuiShowLuxury:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end )
  Controls.CuiShowLuxury:SetSelected(cui_ShowLuxury);

  cui_ShowBonus = CuiSettings:GetBoolean(CuiSettings.SHOW_BONUS);
  Controls.CuiShowBonus:RegisterCallback( Mouse.eLClick, CuiOnToggleBonus );
  Controls.CuiShowBonus:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end )
  Controls.CuiShowBonus:SetSelected(cui_ShowBonus);
end

-- CUI =======================================================================
function CuiGetFoodIncrement(data:table)
  local iModifiedFood;
  local foodIncrement:number;
  if data.TurnsUntilGrowth > - 1 then
    local growthModifier = math.max(1 + (data.HappinessGrowthModifier / 100) + data.OtherGrowthModifiers, 0);
    iModifiedFood = Round(data.FoodSurplus * growthModifier, 2);
    if data.Occupied then
      foodIncrement = iModifiedFood * data.OccupationMultiplier;
    else
      foodIncrement = iModifiedFood * data.HousingMultiplier;
    end
  else
    foodIncrement = data.FoodSurplus;
  end
  return foodIncrement;
end

-- CUI =======================================================================
-- sort resources by type, luxury -> strategic
function CuiCmpResource(t, a, b)
  local oa = 1;
  if t[a].IsStrategic  then oa = 3;
  elseif t[a].IsLuxury then oa = 2;
  end
  local ob = 1;
  if t[b].IsStrategic  then ob = 3;
  elseif t[b].IsLuxury then ob = 2;
  end
  return oa > ob;
end

-- BRS =======================================================================
function GetFontIconForDistrict(sDistrictType:string)
  -- exceptions first
  if sDistrictType == "DISTRICT_CITY_CENTER"                 then return "[ICON_DISTRICT_CITYCENTER]";    end
  if sDistrictType == "DISTRICT_HOLY_SITE"                   then return "[ICON_DISTRICT_HOLYSITE]";      end
  if sDistrictType == "DISTRICT_ENTERTAINMENT_COMPLEX"       then return "[ICON_DISTRICT_ENTERTAINMENT]"; end
  if sDistrictType == "DISTRICT_WATER_ENTERTAINMENT_COMPLEX" then return "[ICON_DISTRICT_ENTERTAINMENT]"; end -- no need to check for mutuals with that
  if sDistrictType == "DISTRICT_AERODROME"                   then return "[ICON_DISTRICT_WONDER]";        end -- no unique font icon for an aerodrome
  -- default icon last
  return "[ICON_"..sDistrictType.."]";
end

-- BRS =======================================================================
local m_DistrictsOrder:table = {
  -- Ancient Era
  --"DISTRICT_GOVERNMENT", -- to save space, will be treated separately
  "DISTRICT_HOLY_SITE", -- icon is DISTRICT_HOLYSITE
  "DISTRICT_CAMPUS",
  "DISTRICT_ENCAMPMENT",
  -- Classical Era
  "DISTRICT_THEATER",
  "DISTRICT_COMMERCIAL_HUB",
  "DISTRICT_HARBOR",
  "DISTRICT_ENTERTAINMENT_COMPLEX", -- with DISTRICT_WATER_ENTERTAINMENT_COMPLEX, icon is DISTRICT_ENTERTAINMENT
  -- Medieval Era
  "DISTRICT_INDUSTRIAL_ZONE",
  -- others
  "DISTRICT_AQUEDUCT",
  "DISTRICT_NEIGHBORHOOD",
  "DISTRICT_SPACEPORT",
  "DISTRICT_AERODROME", -- no icon, we'll use an icon for DISTRICT_WONDER
}

-- BRS =======================================================================
function HasCityDistrict(kCityData:table, sDistrictType:string)
  for _,district in ipairs(kCityData.BuildingsAndDistricts) do
    if district.isBuilt then
      local sDistrictInCity:string = district.Type;
      --if district.DistrictType == sDistrictType then return true; end
      if GameInfo.DistrictReplaces[ sDistrictInCity ] then sDistrictInCity = GameInfo.DistrictReplaces[ sDistrictInCity ].ReplacesDistrictType; end
      if sDistrictInCity == sDistrictType then return true; end
      -- check mutually exclusive
      for row in GameInfo.MutuallyExclusiveDistricts() do
        if sDistrictInCity == row.District and row.MutuallyExclusiveDistrict == sDistrictType then return true; end
      end
    end
  end
  return false;
end

-- BRS =======================================================================
function GetDistrictsForCity(kCityData:table)
  local sDistricts:string = "";
  for _,districtType in ipairs(m_DistrictsOrder) do
    local sDistrictIcon:string = "[ICON_Bullet]"; -- default empty
    if HasCityDistrict(kCityData, districtType) then
      sDistrictIcon = GetFontIconForDistrict(districtType);
    end
    sDistricts = sDistricts .. sDistrictIcon;
  end
  return sDistricts;
end

-- ===========================================================================
function CuiRedGreenNumber(num)
  if num > 0 then
    return "[COLOR: 80,255,90,160]+" .. tostring(num) .. "[ENDCOLOR]";
  elseif num < 0 then
    return "[COLOR: 255,40,50,160]"  .. tostring(num) .. "[ENDCOLOR]";
  else
    -- return "[COLOR_White]"          .. tostring(num) .. "[ENDCOLOR]";
    return tostring(num);
  end
end

-- ===========================================================================
function Initialize()

  -- UI Callbacks
  ContextPtr:SetInitHandler( OnInit );
  ContextPtr:SetInputHandler( OnInputHandler, true );
  Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnCloseButton );
  Controls.CloseButton:RegisterCallback(	Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
  Controls.CollapseAll:RegisterCallback( Mouse.eLClick, OnCollapseAllButton );
  Controls.CollapseAll:RegisterCallback(	Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
  CuiInit(); -- CUI
  
  -- Events
  LuaEvents.TopPanel_OpenReportsScreen.Add( OnTopOpenReportsScreen );
  LuaEvents.TopPanel_CloseReportsScreen.Add( OnTopCloseReportsScreen );
  LuaEvents.ReportsList_OpenCityStatus.Add( OnOpenCityStatus );
  LuaEvents.ReportsList_OpenResources.Add( OnOpenResources );
  LuaEvents.ReportsList_OpenYields.Add( OnTopOpenReportsScreen );
  LuaEvents.ReportsList_OpenDeals.Add( OnOpenDeals ); -- CUI

  Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );
end
Initialize();
