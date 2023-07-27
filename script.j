//Just to avoid arithmatic errors when using comparisons,
//use this instead of 0.00.
constant function GetZeroLikeValueForSpellTime takes nothing returns real
    return 0.001
endfunction

function SetSpellGUIVarsFromIndex takes integer index returns nothing
    set udg_Spell__Index           = index
    set udg_Spell__Ability         = udg_Spell_i_Abil[udg_Spell_i_Head[index]]
    set udg_Spell__Caster          = udg_Spell_i_Caster[index]
    set udg_Spell__CasterOwner     = GetOwningPlayer(udg_Spell__Caster)
    set udg_Spell__Level           = udg_Spell_i_Level[index]
    set udg_Spell__LevelMultiplier = udg_Spell__Level //Spell__LevelMultiplier is a real variable.
    set udg_Spell__Target          = udg_Spell_i_Target[index]
    set udg_Spell__TargetGroup     = udg_Spell_i_TargetGroup[index]
    set udg_Spell__Completed       = udg_Spell_i_Completed[index]
    set udg_Spell__Channeling      = udg_Spell_i_Channeling[index]

    //"Magic" to ensure the locations never leak.
    call MoveLocation(udg_Spell__CastPoint, GetUnitX(udg_Spell__Caster), GetUnitY(udg_Spell__Caster))
    if udg_Spell__Target == null then
        call MoveLocation(udg_Spell__TargetPoint, udg_Spell_i_TargetX[index], udg_Spell_i_TargetY[index])
    else
        call MoveLocation(udg_Spell__TargetPoint, GetUnitX(udg_Spell__Target), GetUnitY(udg_Spell__Target))
    endif    
endfunction

//DEPRECATED - Exists for backwards-compatibility for advanced users who were manually calling this.
function SpellIndexGetVars takes integer index returns nothing
    call SetSpellGUIVarsFromIndex(index)
endfunction

function ApplySpellFiltersFromHead takes integer head returns nothing
    set udg_Spell_i_AllowEnemy[head]       = udg_Spell__Filter_AllowEnemy
    set udg_Spell_i_AllowAlly[head]        = udg_Spell__Filter_AllowAlly
    set udg_Spell_i_AllowDead[head]        = udg_Spell__Filter_AllowDead
    set udg_Spell_i_AllowLiving[head]      = udg_Spell__Filter_AllowLiving
    set udg_Spell_i_AllowMagicImmune[head] = udg_Spell__Filter_AllowMagicImmune
    set udg_Spell_i_AllowMechanical[head]  = udg_Spell__Filter_AllowMechanical
    set udg_Spell_i_AllowStructure[head]   = udg_Spell__Filter_AllowStructure
    set udg_Spell_i_AllowFlying[head]      = udg_Spell__Filter_AllowFlying
    set udg_Spell_i_AllowHero[head]        = udg_Spell__Filter_AllowHero
    set udg_Spell_i_AllowNonHero[head]     = udg_Spell__Filter_AllowNonHero
endfunction

function SpellIndexDestroy takes integer index returns nothing
    local integer indexOf
    local integer stackN
    if udg_Spell_i_RecycleList[index] > -1 then
        //It was already destroyed
        return
    endif

    //Don't destroy the spell until the caster has finished channeling it
    if not udg_Spell_i_Channeling[index] then
        set udg_Spell_i_RecycleList[index] = udg_Spell_i_Recycle
        set udg_Spell_i_Recycle = index
       
        //Reset things to defaults:
        set udg_Spell_i_Time[index] = 0.00
        set udg_Spell_i_LastTime[index] = 0.00
        set udg_Spell_i_Duration[index] = 0.00
        set udg_Spell_i_Completed[index] = false
        set udg_Spell_i_Caster[index] = null
        set udg_Spell_i_Target[index] = null
        set udg_Spell_i_OnLoopStack[index] = null
       
        //Recycle any applicable target unit group.
        if udg_Spell_i_TargetGroup[index] != null then
            call GroupClear(udg_Spell_i_TargetGroup[index])
            set udg_Spell_i_GroupStack[udg_Spell_i_GroupN] = udg_Spell_i_TargetGroup[index]
            set udg_Spell_i_GroupN = udg_Spell_i_GroupN + 1
            set udg_Spell_i_TargetGroup[index] = null
        endif
       
        //Clear any user-specified data in the hashtable:
        call FlushChildHashtable(udg_Spell__Hash, index)
        //call BJDebugMsg("Destroying index: " + I2S(index))
    endif
   
    set indexOf = udg_Spell_i_StackRef[index]
    if indexOf != -1 then
        set stackN = udg_Spell_i_StackN - 1
        set udg_Spell_i_StackN = stackN
       
        set udg_Spell_i_StackRef[udg_Spell_i_Stack[stackN]] = indexOf
        set udg_Spell_i_Stack[indexOf] = udg_Spell_i_Stack[stackN]
        if stackN == 0 then
            //If no more spells require the timer, pause it.
            call PauseTimer(udg_Spell_i_Timer)
        endif
        set udg_Spell_i_StackRef[stackN] = -1
    endif
endfunction

function SpellIndexExecuteTrigger takes integer index, trigger trig returns real
    local real    prevDuration    = udg_Spell_i_Duration[index]
    local real    zero            = GetZeroLikeValueForSpellTime()
    local integer head            = udg_Spell_i_Head[index]
    local boolean durationChanged = false

    set udg_Spell__Duration = prevDuration
    set udg_Spell__Time = 0.00
    
    if trig != null then
        set udg_Spell__Trigger_OnLoop = null
        set udg_Spell__Expired = prevDuration <= zero
        call SetSpellGUIVarsFromIndex(index)
        if TriggerEvaluate(trig) then
            call TriggerExecute(trig)
        endif
        if udg_Spell__Trigger_OnLoop != null then
            set udg_Spell_i_OnLoopStack[index] = udg_Spell__Trigger_OnLoop
        endif

        //The remaining lines in this function process the duration specified by the user.
        
        if udg_Spell__StartDuration then
            set udg_Spell__StartDuration = false
            set udg_Spell__Duration = udg_Spell_i_Duration[head] + udg_Spell_i_LastTime[head] * udg_Spell__LevelMultiplier

        elseif (udg_Spell__Duration <= zero) or (udg_Spell__Expired and prevDuration > zero) then
            //The spell duration ended naturally, or the user manually expired it.
            set udg_Spell__Duration = 0.00
            return udg_Spell__Time
        endif
        if udg_Spell__Time <= zero then
            if udg_Spell_i_LastTime[index] <= zero then
                if udg_Spell_i_Time[head] > zero then
                    //The user specified a default interval to follow:
                    set udg_Spell__Time = udg_Spell_i_Time[head]
                else
                    //Set the spell time to the minimum.
                    set udg_Spell__Time = udg_Spell__Interval
                endif
            else
                //Otherwise, set it to what it was before.
                set udg_Spell__Time = udg_Spell_i_LastTime[index]
            endif
        //otherwise, the user is specifying a new time for the spell.
        endif

        set udg_Spell_i_LastTime[index] = udg_Spell__Time //In any case, remember this time.
        if prevDuration != udg_Spell__Duration then
            set udg_Spell_i_Duration[index] = udg_Spell__Duration
        else
            set udg_Spell_i_Duration[index] = udg_Spell__Duration - udg_Spell__Time
        endif
        set udg_Spell__Duration = 0.00
    endif
    return udg_Spell__Time
endfunction

//===========================================================================
// Runs every Spell__Interval seconds and handles all of the timed events.
//
function SpellTimedLoopCallback takes nothing returns nothing
    local integer stackN = udg_Spell_i_StackN
    local integer spellIndex
    local real timeLeft
    local real zero = GetZeroLikeValueForSpellTime()
    local boolean toExpire
    set udg_Spell__Running = true
    loop
        //Run stack top to bottom to avoid skipping slots when destroying.
        set stackN = stackN - 1
        exitwhen stackN < 0
        set spellIndex = udg_Spell_i_Stack[stackN]

        set timeLeft = udg_Spell_i_Time[spellIndex] - udg_Spell__Interval

        set toExpire = timeLeft <= zero
        if toExpire then
            set timeLeft = SpellIndexExecuteTrigger(spellIndex, udg_Spell_i_OnLoopStack[spellIndex])
            set toExpire = timeLeft <= zero
        endif

        if toExpire then
            call SpellIndexDestroy(spellIndex)
        else
            set udg_Spell_i_Time[spellIndex] = timeLeft
        endif
    endloop
    set udg_Spell__Running = false
endfunction

//===========================================================================
// This handles all of the native the event responses.
//
function RunNativeSpellEvent takes nothing returns boolean
    local integer         abilId = GetSpellAbilityId()
    local integer         casterId
    local integer         head = LoadInteger(udg_Spell__Hash, 0, abilId)
    local integer         spellIndex
    local playerunitevent eventId
    local real            zero = GetZeroLikeValueForSpellTime()
    local trigger         trig
    if head == 0 then
        //Nothing for this ability has been registered. Skip the sequence.
        return false
    endif
    set eventId           = ConvertPlayerUnitEvent(GetHandleId(GetTriggerEventId()))
    set udg_Spell__Caster = GetTriggerUnit()
    set casterId          = GetHandleId(udg_Spell__Caster)
    set spellIndex        = LoadInteger(udg_Spell__Hash, abilId, casterId)
    if spellIndex == 0 then
        set spellIndex = udg_Spell_i_Recycle
        if spellIndex == 0 then
            //Create a new, unique index
            set spellIndex = udg_Spell_i_Instances + 1
            set udg_Spell_i_Instances = spellIndex
        else
            //Repurpose an existing one
            set udg_Spell_i_Recycle = udg_Spell_i_RecycleList[spellIndex]
        endif
        //call BJDebugMsg("Creating index: " + I2S(spellIndex))
        set udg_Spell_i_RecycleList[spellIndex] = -1
        set udg_Spell_i_StackRef[spellIndex] = -1
        set udg_Spell_i_Head[spellIndex] = head

        if eventId == EVENT_PLAYER_UNIT_SPELL_CHANNEL then
            //Usually, a spell is initialized with this event.
            set udg_Spell_i_Channeling[spellIndex] = true
            call SaveInteger(udg_Spell__Hash, abilId, casterId, spellIndex)
            set trig = udg_Spell_i_OnChannelStack[head]
        else
            //However, in the case of Charge Gold and Lumber,
            //only EVENT_PLAYER_UNIT_SPELL_EFFECT will run.
            set trig = udg_Spell_i_OnEffectStack[head]
        endif
        set udg_Spell_i_Caster[spellIndex] = udg_Spell__Caster
        set udg_Spell_i_Level[spellIndex] = GetUnitAbilityLevel(udg_Spell__Caster, abilId)
        set udg_Spell_i_Target[spellIndex] = GetSpellTargetUnit()
        set udg_Spell_i_TargetX[spellIndex] = GetSpellTargetX()
        set udg_Spell_i_TargetY[spellIndex] = GetSpellTargetY()
       
        set udg_Spell_i_OnLoopStack[spellIndex] = udg_Spell_i_OnLoopStack[head]
        if udg_Spell_i_UseTG[head] then
            if udg_Spell_i_GroupN > 0 then
                //Pop a recycled group off of the stack
                set udg_Spell_i_GroupN = udg_Spell_i_GroupN - 1
                set udg_Spell_i_TargetGroup[spellIndex] = udg_Spell_i_GroupStack[udg_Spell_i_GroupN]
            else
                set udg_Spell_i_TargetGroup[spellIndex] = CreateGroup()
            endif
        endif
    elseif eventId == EVENT_PLAYER_UNIT_SPELL_CAST then
        set trig = udg_Spell_i_OnCastStack[head]
    elseif eventId == EVENT_PLAYER_UNIT_SPELL_EFFECT then
        set trig = udg_Spell_i_OnEffectStack[head]
    elseif eventId == EVENT_PLAYER_UNIT_SPELL_FINISH then
        set udg_Spell_i_Completed[spellIndex] = true
        return true
    else //eventId == EVENT_PLAYER_UNIT_SPELL_ENDCAST
        set udg_Spell_i_Channeling[spellIndex] = false
        call RemoveSavedInteger(udg_Spell__Hash, abilId, casterId)
        set trig = udg_Spell_i_OnFinishStack[head]
    endif
    if SpellIndexExecuteTrigger(spellIndex, trig) > zero then
        //Set the spell time to the user-specified one.
        set udg_Spell_i_Time[spellIndex] = udg_Spell__Time
        if udg_Spell_i_StackRef[spellIndex] == -1 then
            //Allocate the spell index onto the loop stack.
            set abilId = udg_Spell_i_StackN
            set udg_Spell_i_Stack[abilId] = spellIndex
            set udg_Spell_i_StackRef[spellIndex] = abilId
            set udg_Spell_i_StackN = abilId + 1
            if abilId == 0 then
                //If this is the first spell index using the timer, start it up:
                call TimerStart(udg_Spell_i_Timer, udg_Spell__Interval, true, function SpellTimedLoopCallback)
            endif
        endif
    elseif (not udg_Spell_i_Channeling[spellIndex]) and (trig != null or udg_Spell_i_Time[spellIndex] <= zero) then
        call SpellIndexDestroy(spellIndex)
    endif
    set trig = null
    return true
endfunction

function RunRecursiveSpellEvent takes nothing returns nothing
    local integer prevIndex    = udg_Spell__Index
    local real    prevTime     = udg_Spell__Time
    local real    prevDuration = udg_Spell__Duration
    local boolean prevExpired  = udg_Spell__Expired

    if udg_Spell__Trigger_OnLoop != null then
        set udg_Spell_i_OnLoopStack[prevIndex] = udg_Spell__Trigger_OnLoop
    endif

    if RunNativeSpellEvent() then
        set udg_Spell__Time     = prevTime
        set udg_Spell__Duration = prevDuration
        set udg_Spell__Expired  = prevExpired
        call SetSpellGUIVarsFromIndex(prevIndex)
    endif
endfunction

//===========================================================================
// Base function of the system: runs when an ability event is triggered.
//
function NativeSpellEventCallback takes nothing returns boolean
    if udg_Spell__Running then
        call RunRecursiveSpellEvent()
    else
        set udg_Spell__Running = true

        call RunNativeSpellEvent()
        
        set udg_Spell__Running = false
    endif
    return false
endfunction

//===========================================================================
// Set Spell__Ability to your spell's ability
// Set Spell__Trigger_OnChannel/Cast/Effect/Finish/Loop to any trigger(s) you
// want to automatically run.
//
// GUI-friendly: Run Spell System <gen> (ignoring conditions)
// JASS-friendly: simply call this function.
//
function SpellSystemRegister takes nothing returns nothing
    local integer abilId = udg_Spell__Ability
    local integer head = udg_Spell_i_Instances + 1
   
    if HaveSavedInteger(udg_Spell__Hash, 0, abilId) or abilId == 0 then
        if abilId == 0 then
            call BJDebugMsg("Null ability ID passed to Spell System")
        else
            call BJDebugMsg("Duplicate ability ID passed to Spell System: " + I2S(abilId))
        endif

        return //error
    endif
    set udg_Spell_i_Instances = head
    set udg_Spell_i_Abil[head] = abilId
   
    //Preload the ability on dummy unit to help prevent first-instance lag
    call UnitAddAbility(udg_Spell_i_PreloadDummy, abilId)
   
    //Save head index to the spell ability so it be referenced later.
    call SaveInteger(udg_Spell__Hash, 0, abilId, head)
   
    //Set any applicable event triggers.
    set udg_Spell_i_OnChannelStack[head] = udg_Spell__Trigger_OnChannel
    set udg_Spell_i_OnCastStack[head]    = udg_Spell__Trigger_OnCast
    set udg_Spell_i_OnEffectStack[head]  = udg_Spell__Trigger_OnEffect
    set udg_Spell_i_OnFinishStack[head]  = udg_Spell__Trigger_OnFinish
    set udg_Spell_i_OnLoopStack[head]    = udg_Spell__Trigger_OnLoop
    set udg_Spell_i_InRangeFilter[head]  = udg_Spell__Trigger_InRangeFilter

    //Set any customized filter variables:
    call ApplySpellFiltersFromHead(head)
   
    //Tell the system to automatically create target groups, if needed
    set udg_Spell_i_AutoAddTargets[head] = udg_Spell__AutoAddTargets
    set udg_Spell_i_UseTG[head]          = udg_Spell__UseTargetGroup or udg_Spell__AutoAddTargets
   
    //Handle automatic buff assignment
    set udg_Spell_i_BuffAbil[head]  = udg_Spell__BuffAbility
    set udg_Spell_i_BuffOrder[head] = udg_Spell__BuffOrder
   
    //Set the default time sequences if a duration is used:
    set udg_Spell_i_Time[head]     = udg_Spell__Time
    set udg_Spell_i_Duration[head] = udg_Spell__Duration
    set udg_Spell_i_LastTime[head] = udg_Spell__DurationPerLevel
   
    //Set variables back to their defaults:
    set udg_Spell__Trigger_OnChannel     = null
    set udg_Spell__Trigger_OnCast        = null
    set udg_Spell__Trigger_OnEffect      = null
    set udg_Spell__Trigger_OnFinish      = null
    set udg_Spell__Trigger_OnLoop        = null
    set udg_Spell__Trigger_InRangeFilter = null
    set udg_Spell__AutoAddTargets        = false
    set udg_Spell__UseTargetGroup        = false
    set udg_Spell__Time                  = 0.00
    set udg_Spell__Duration              = 0.00
    set udg_Spell__DurationPerLevel      = 0.00
    set udg_Spell__BuffAbility           = 0
    set udg_Spell__BuffOrder             = 0
   
    set udg_Spell__Filter_AllowEnemy       = udg_Spell_i_AllowEnemy[0]
    set udg_Spell__Filter_AllowAlly        = udg_Spell_i_AllowAlly[0]
    set udg_Spell__Filter_AllowDead        = udg_Spell_i_AllowDead[0]
    set udg_Spell__Filter_AllowMagicImmune = udg_Spell_i_AllowMagicImmune[0]
    set udg_Spell__Filter_AllowMechanical  = udg_Spell_i_AllowMechanical[0]
    set udg_Spell__Filter_AllowStructure   = udg_Spell_i_AllowStructure[0]
    set udg_Spell__Filter_AllowFlying      = udg_Spell_i_AllowFlying[0]
    set udg_Spell__Filter_AllowHero        = udg_Spell_i_AllowHero[0]
    set udg_Spell__Filter_AllowNonHero     = udg_Spell_i_AllowNonHero[0]
    set udg_Spell__Filter_AllowLiving      = udg_Spell_i_AllowLiving[0]
endfunction

//===========================================================================
// Before calling this function, set Spell__InRangePoint to whatever point
// you need, THEN set Spell__InRange to the radius you need. The system will
// enumerate the units matching the configured filter and fill them into
// Spell_InRangeGroup.
//
function SpellGroupUnitsInRange takes nothing returns boolean
    local integer head = udg_Spell_i_Head[udg_Spell__Index]
    local integer inRangeN = 0
    local unit pickedUnit
    local real padding = 64.00
    if udg_Spell_i_AllowStructure[head] then
        //A normal unit can only have up to size 64.00 collision, but if the
        //user needs to check for structures we need a padding big enough for
        //the "fattest" ones: Tier 3 town halls.
        set padding = 197.00
    endif
    call GroupEnumUnitsInRangeOfLoc(udg_Spell__InRangeGroup, udg_Spell__InRangePoint, udg_Spell__InRange + padding, null)
    loop
        set pickedUnit = FirstOfGroup(udg_Spell__InRangeGroup)
        exitwhen pickedUnit == null
        call GroupRemoveUnit(udg_Spell__InRangeGroup, pickedUnit)
        loop
            exitwhen udg_Spell_i_AutoAddTargets[head] and IsUnitInGroup(pickedUnit, udg_Spell__TargetGroup)

            exitwhen not IsUnitInRangeLoc(pickedUnit, udg_Spell__InRangePoint, udg_Spell__InRange)

            if IsUnitType(pickedUnit, UNIT_TYPE_DEAD) then
                exitwhen not udg_Spell_i_AllowDead[head]
            else
                exitwhen not udg_Spell_i_AllowLiving[head]
            endif
            
            if IsUnitAlly(pickedUnit, udg_Spell__CasterOwner) then
                exitwhen not udg_Spell_i_AllowAlly[head]
            else
                exitwhen not udg_Spell_i_AllowEnemy[head]
            endif
            
            if IsUnitType(pickedUnit, UNIT_TYPE_HERO) or IsUnitType(pickedUnit, UNIT_TYPE_RESISTANT) then
                exitwhen not udg_Spell_i_AllowHero[head]
            else
                exitwhen not udg_Spell_i_AllowNonHero[head]
            endif

            exitwhen not udg_Spell_i_AllowStructure[head]   and IsUnitType(pickedUnit, UNIT_TYPE_STRUCTURE)
            exitwhen not udg_Spell_i_AllowFlying[head]      and IsUnitType(pickedUnit, UNIT_TYPE_FLYING)
            exitwhen not udg_Spell_i_AllowMechanical[head]  and IsUnitType(pickedUnit, UNIT_TYPE_MECHANICAL)
            exitwhen not udg_Spell_i_AllowMagicImmune[head] and IsUnitType(pickedUnit, UNIT_TYPE_MAGIC_IMMUNE)
            
            set udg_Spell__InRangeUnit = pickedUnit

            //Run the user's designated filter, if one exists.
            exitwhen udg_Spell_i_InRangeFilter[head] != null and not TriggerEvaluate(udg_Spell_i_InRangeFilter[head])

            //Push the unit onto the list
            set inRangeN = inRangeN + 1
            set udg_Spell__InRangeUnits[inRangeN] = pickedUnit

            //This doesn't actually loop; it functions moreso as a complex switch statement.
            exitwhen true
        endloop
    endloop

    if inRangeN > udg_Spell__InRangeMax and udg_Spell__InRangeMax > 0 then
        //The user has defined a maximum number of units allowed in the group.
        //Remove a random unit until the total does not exceed capacity.
        loop
            set udg_Spell__InRangeUnits[GetRandomInt(1, inRangeN)] = udg_Spell__InRangeUnits[inRangeN]
            set inRangeN = inRangeN - 1
            exitwhen inRangeN == udg_Spell__InRangeMax
        endloop
    endif

    set udg_Spell__InRangeCount = inRangeN
    set udg_Spell__InRangeMax = 0
    set udg_Spell__InRange = 0.00
    loop
        exitwhen inRangeN == 0
        set pickedUnit = udg_Spell__InRangeUnits[inRangeN]
        call GroupAddUnit(udg_Spell__InRangeGroup, pickedUnit)
        if udg_Spell_i_AutoAddTargets[head] then
            call GroupAddUnit(udg_Spell__TargetGroup, pickedUnit)
        endif
        if udg_Spell__WakeTargets and UnitIsSleeping(pickedUnit) then
            call UnitWakeUp(pickedUnit)
        endif
        if udg_Spell_i_BuffAbil[head] != 0 and udg_Spell_i_BuffOrder[head] != 0 then
            //Auto-buff units added to group:
            call UnitAddAbility(udg_Spell_i_PreloadDummy, udg_Spell_i_BuffAbil[head])
            call IssueTargetOrderById(udg_Spell_i_PreloadDummy, udg_Spell_i_BuffOrder[head], pickedUnit)
            call UnitRemoveAbility(udg_Spell_i_PreloadDummy, udg_Spell_i_BuffAbil[head])
        endif
        set inRangeN = inRangeN - 1
    endloop
    set pickedUnit = null
    return false
endfunction

function SpellSystem__OnGameStartedCallback takes nothing returns nothing
    local integer dummyIndex = udg_Spell_i_Instances
    loop
        exitwhen dummyIndex == 0
        //Remove preloaded abilities so they don't interfere with orders
        call UnitRemoveAbility(udg_Spell_i_PreloadDummy, udg_Spell_i_Abil[udg_Spell_i_Head[dummyIndex]])
        set dummyIndex = dummyIndex - 1
    endloop
endfunction

//===========================================================================
function InitTrig_Spell_System takes nothing returns nothing
    local integer playerIndex = bj_MAX_PLAYER_SLOTS
    local trigger trig
    local player forPlayer
   
    if gg_trg_Spell_System != null then
        //A JASS function call already initialized the system.
        return
    endif
   
    //This runs before map init events so the hashtable is ready before then.
    set udg_Spell__Hash = InitHashtable()
   
    //Initialize these two locations which will never get removed
    set udg_Spell__CastPoint = Location(0, 0)
    set udg_Spell__TargetPoint = Location(0, 0)
   
    //GUI automatically initializes group variables for udg_ unit groups.
    //What I'm doing here is recycling those existing ones by filling them into the group recycle stack array.
    //group stack [0] and [1] are already populated.
    set udg_Spell_i_GroupStack[2] = udg_Spell__TargetGroup
    set udg_Spell_i_GroupStack[3] = udg_Spell_i_TargetGroup[0]
    set udg_Spell_i_GroupStack[4] = udg_Spell_i_TargetGroup[1]
    set udg_Spell_i_GroupN = 5 //total number of groups that already exist in the stack at the start of the game.
   
    set trig = CreateTrigger()
    call TriggerRegisterVariableEvent(trig, "udg_Spell__InRange", GREATER_THAN, 0.00)
    call TriggerAddCondition(trig, Filter(function SpellGroupUnitsInRange))
   
    set trig = CreateTrigger()
    call TriggerAddCondition(trig, Filter(function NativeSpellEventCallback))
    loop
        set playerIndex = playerIndex - 1
        set forPlayer = Player(playerIndex)
        call TriggerRegisterPlayerUnitEvent(trig, forPlayer, EVENT_PLAYER_UNIT_SPELL_CHANNEL, null)
        call TriggerRegisterPlayerUnitEvent(trig, forPlayer, EVENT_PLAYER_UNIT_SPELL_CAST, null)
        call TriggerRegisterPlayerUnitEvent(trig, forPlayer, EVENT_PLAYER_UNIT_SPELL_EFFECT, null)
        call TriggerRegisterPlayerUnitEvent(trig, forPlayer, EVENT_PLAYER_UNIT_SPELL_FINISH, null)
        call TriggerRegisterPlayerUnitEvent(trig, forPlayer, EVENT_PLAYER_UNIT_SPELL_ENDCAST, null)
        exitwhen playerIndex == 0
    endloop
   
    //Run the configuration trigger so its variables are ready before the
    //map initialization events run.
    call TriggerExecute(gg_trg_Spell_System_Config)

    call ApplySpellFiltersFromHead(0)
   
    //Create this trigger so it's GUI-friendly.
    set gg_trg_Spell_System = CreateTrigger()
    call TriggerAddAction(gg_trg_Spell_System, function SpellSystemRegister)

    //In case the user accidentally registers using this one, allow it.
    set gg_trg_Spell_System_Config = gg_trg_Spell_System
   
    //Create a dummy unit for preloading abilities and casting buffs.
    set udg_Spell_i_PreloadDummy = CreateUnit(udg_Spell__DummyOwner, udg_Spell__DummyType, 0, 0, 0)
   
    //Start the timer to remove its abilities:
    call TimerStart(udg_Spell_i_Timer, 0.00, false, function SpellSystem__OnGameStartedCallback)
    call UnitRemoveAbility(udg_Spell_i_PreloadDummy, 'Amov') //Force it to never move to cast spells

    set forPlayer = null
    set trig = null
endfunction
