-- ===========================================================================
-- Cui Unit List Button
-- eudaimonia, 2/18/2019
-- ===========================================================================

local isAttached = false;
local unitListButtonInstance = {};

-- ===========================================================================
function OnToggleUnitList()
  LuaEvents.CuiToggleUnitList();
end

-- ===========================================================================
function AttachToTopPanel()
  if not isAttached then
    local buttonStack = ContextPtr:LookUpControl( "/InGame/LaunchBar/ButtonStack" );
    ContextPtr:BuildInstanceForControl("CuiUnitList", unitListButtonInstance, buttonStack );
    unitListButtonInstance.UnitListButton:RegisterCallback(Mouse.eLClick, OnToggleUnitList);
    unitListButtonInstance.UnitListButton:SetToolTipString(Locale.Lookup("LOC_PEDIA_UNITS_TITLE"));
    buttonStack:CalculateSize();
    
    local backing = ContextPtr:LookUpControl( "/InGame/LaunchBar/LaunchBacking" );
    backing:SetSizeX(buttonStack:GetSizeX() + 116);
    
    local backingTile = ContextPtr:LookUpControl( "/InGame/LaunchBar/LaunchBackingTile" );
    backingTile:SetSizeX(buttonStack:GetSizeX() - 20);
    
    LuaEvents.LaunchBar_Resize(buttonStack:GetSizeX());
    isAttached = true;
  end
end

-- ===========================================================================
function CuiOnIngameAction(actionId)
  if Game.GetLocalPlayer() == -1 then return; end
  
  if actionId == Input.GetActionId("CuiActionToggleUnitList") then
    OnToggleUnitList();
  end
end

-- ===========================================================================
function Initialize()
  ContextPtr:SetHide( true );
  Events.LoadGameViewStateDone.Add(AttachToTopPanel);
  Events.InputActionTriggered.Add(CuiOnIngameAction);
end
Initialize();