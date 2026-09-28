-- =============================================================
-- AUST_trucker / client/carry_system.lua
-- Sistema de Carga Física — Prop attach + carry animation
-- Módulo reutilizável para carregar objetos fisicamente
-- =============================================================

CarrySystem = {}

local _active    = false
local _propEntity = nil
local _animDict  = nil
local _controlThread = nil

-- =====================
-- CORE API
-- =====================

---Inicia carry: attacha prop no ped e inicia animação
---@param carryType string  key em Config.CarryProps (ex: 'small_box', 'barrel')
---@return boolean
function CarrySystem.Start(carryType)
    if _active then return false end

    local cfg = Config.CarryProps and Config.CarryProps[carryType]
    if not cfg then
        if Config.Debug then print('[CarrySystem] Tipo desconhecido: ' .. tostring(carryType)) end
        return false
    end

    local ped = cache.ped or PlayerPedId()
    local model = joaat(cfg.model)

    -- Carregar modelo
    lib.requestModel(model, 5000)
    if not HasModelLoaded(model) then
        if Config.Debug then print('[CarrySystem] Falha ao carregar modelo: ' .. cfg.model) end
        return false
    end

    -- Carregar animação
    _animDict = cfg.anim.dict
    lib.requestAnimDict(_animDict, 5000)

    -- Criar e attachar prop
    local coords = GetEntityCoords(ped)
    _propEntity = CreateObject(model, coords.x, coords.y, coords.z, true, true, true)
    SetModelAsNoLongerNeeded(model)

    AttachEntityToEntity(
        _propEntity, ped,
        GetPedBoneIndex(ped, cfg.bone),
        cfg.offset.x, cfg.offset.y, cfg.offset.z,
        cfg.rot.x, cfg.rot.y, cfg.rot.z,
        true, true, false, true, 1, true
    )

    -- Animação de carry (looped)
    TaskPlayAnim(ped, _animDict, cfg.anim.clip, 3.0, 3.0, -1, 49, 0, false, false, false)

    _active = true

    -- Thread de controle: bloqueia armas e reduz velocidade
    _controlThread = CreateThread(function()
        while _active do
            local p = cache.ped or PlayerPedId()

            -- Bloquear armas
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)  -- Attack
            DisableControlAction(0, 25, true)  -- Aim
            DisableControlAction(0, 47, true)  -- Weapon
            DisableControlAction(0, 58, true)  -- Weapon
            DisableControlAction(0, 263, true) -- Melee

            -- Bloquear sprint (permitir andar/correr leve)
            if Config.ManualLoading and Config.ManualLoading.SpeedReduction then
                DisableControlAction(0, 21, true)  -- Sprint
            end

            -- Se cair/morrer, soltar prop
            if IsEntityDead(p) or IsPedRagdoll(p) then
                CarrySystem.Stop()
                break
            end

            Wait(0)
        end
    end)

    return true
end

---Para carry: remove prop e limpa animação
function CarrySystem.Stop()
    if not _active then return end

    local ped = cache.ped or PlayerPedId()

    -- Remover prop
    if _propEntity and DoesEntityExist(_propEntity) then
        DetachEntity(_propEntity, true, true)
        DeleteEntity(_propEntity)
    end
    _propEntity = nil

    -- Limpar animação
    if _animDict then
        StopAnimTask(ped, _animDict, 'idle', 1.0)
        ClearPedTasks(ped)
    end
    _animDict = nil

    _active = false
    _controlThread = nil
end

---Verifica se está carregando
---@return boolean
function CarrySystem.IsCarrying()
    return _active
end

---Solta prop no chão (para depositar visualmente)
---@param coords? vector3  coordenadas onde soltar (nil = posição atual)
local _droppedProps = {}

function CarrySystem.DropAt(coords)
    if not _active or not _propEntity then return end

    local ped = cache.ped or PlayerPedId()
    local droppedEntity = _propEntity

    -- Desattachar
    DetachEntity(droppedEntity, true, true)

    if coords then
        SetEntityCoords(droppedEntity, coords.x, coords.y, coords.z, false, false, false, false)
    else
        local pedCoords = GetEntityCoords(ped)
        SetEntityCoords(droppedEntity, pedCoords.x, pedCoords.y, pedCoords.z - 0.5, false, false, false, false)
    end
    PlaceObjectOnGroundProperly(droppedEntity)

    table.insert(_droppedProps, droppedEntity)
    -- HARDENING: Auto-deletar prop descartado após 30 segundos para prevenir vazamento de entidades
    SetTimeout(30000, function()
        if DoesEntityExist(droppedEntity) then
            DeleteEntity(droppedEntity)
        end
    end)

    -- Limpar referência ativa
    _propEntity = nil

    -- Limpar animação
    if _animDict then
        StopAnimTask(ped, _animDict, 'idle', 1.0)
        ClearPedTasks(ped)
    end
    _animDict = nil

    _active = false
    _controlThread = nil
end

---Retorna a entidade do prop atual (para cleanup externo)
---@return number?
function CarrySystem.GetPropEntity()
    return _propEntity
end

-- =====================
-- CLEANUP
-- =====================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if _active then CarrySystem.Stop() end
    for _, ent in ipairs(_droppedProps) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    _droppedProps = {}
end)
