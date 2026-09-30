-- =======================================================================
-- AUST_trucker — shared/config.lua
-- Integração Polarix TruckerJob (Stack QBOX / OX)
-- Unificação de Parâmetros: Veículos, Blips, Locais de Entrega e Paletes
-- =======================================================================

Config = Config or {}

Config.Polarix = {
    Framework = 'qbox',
    Target = 'ox_target',
    Debug = false,

    -- Props Exclusivos de Paletes Polarix (Sem props genéricos do GTA V)
    PalletProps = {
        'sm3d_prop_pallet_1',
        'sm3d_prop_pallet_2',
        'sm3d_prop_pallet_1_rep',
        'sm3d_prop_pallet_1_open',
    },
    PalletModels = {
        'sm3d_prop_pallet_1',
        'sm3d_prop_pallet_2',
        'sm3d_prop_pallet_1_rep',
        'sm3d_prop_pallet_1_open',
    },

    DefaultPalletModel = 'sm3d_prop_pallet_1',
    ContainerModel = 'prop_contr_03b_ld',

    PalletWeightKg = 1000,
    MaxPalletsPerOrder = 8,

    -- Coordenadas de Referência do Pátio e Docas (Polarix / Buccaneer)
    Warehouse = {
        Dispatcher = vector4(1268.50, -3175.20, 5.91, 180.00),
        YardManagerPed = 's_m_m_dockwork_01',

        -- Matrizes Dinâmicas de Spawn (OneSync Server-Side Area Clearance)
        TruckSpawns = {
            vector4(1245.79, -3155.76, 4.6, 90.0),
            vector4(1245.79, -3155.76, 4.6, 90.0),
            vector4(1245.09, -3142.37, 4.55, 90.0),
            vector4(1244.53, -3135.57, 4.53, 90.0),
        },

        TrailerSpawns = {
            vector4(1272.21, -3159.80, 4.90, 90.0),
            vector4(1274.77, -3169.75, 4.90, 90.0),
            vector4(1276.19, -3184.77, 4.90, 90.0),
            vector4(1274.23, -3124.46, 4.90, 90.0),
            vector4(1275.04, -3097.47, 4.90, 90.0),
            vector4(1275.68, -3192.90, 4.90, 90.0),
        },

        ForkliftSpawns = {
            vector4(1246.26, -3168.81, 4.63, 90.0),
            vector4(1245.95, -3166.44, 4.61, 90.0),
            vector4(1246.0, -3164.05, 4.62, 90.0),
            vector4(1245.79, -3161.35, 4.6, 90.0),
        },

        PalletSpawns = {
            vector4(1222.81, -3181.3, 4.53, 90.0),
            vector4(1222.89, -3184.15, 4.53, 90.0),
            vector4(1222.89, -3184.15, 4.53, 90.0),
            vector4(1223.03, -3189.05, 4.53, 90.0),
            vector4(1229.41, -3179.9, 4.53, 90.0),
            vector4(1229.41, -3179.9, 4.53, 90.0),
        },

        -- Compatibilidade e Fallbacks
        TruckSpawnCoords = vector4(1245.79, -3155.76, 4.6, 90.0),
        TrailerSpawnCoords = vector4(1272.21, -3159.80, 4.90, 90.0),
        ForkliftBayCoords = vector4(1246.26, -3168.81, 4.63, 90.0),
        HandlerBayCoords = vector4(1240.20, -3195.10, 5.88, 270.00),
        LoadingBayCoords = vector3(1244.53, -3135.57, 4.53),
        PalletStagingAnchor = vector3(1272.00, -3182.00, 5.90),
        PalletStagingHeading = 180.0,
    },

    LoadingBayCoords = vector3(1244.53, -3135.57, 4.53),
    PalletProps = {
        'sm3d_prop_pallet_1',
        'sm3d_prop_pallet_2',
        'sm3d_prop_pallet_1_rep',
        'sm3d_prop_pallet_1_open',
    },

    TrailerSpawns = {
        vector4(1272.21, -3159.80, 4.90, 90.0),
        vector4(1274.77, -3169.75, 4.90, 90.0),
        vector4(1276.19, -3184.77, 4.90, 90.0),
        vector4(1274.23, -3124.46, 4.90, 90.0),
        vector4(1275.04, -3097.47, 4.90, 90.0),
        vector4(1275.68, -3192.90, 4.90, 90.0),
    },

    -- Configuração e Offsets de Empilhadeira (Forklift) - Extraído do Polarix
    Forklift = {
        VehicleModel = 'forklift',
        AttachBone = 'forks_attach',
        ForkBoneIndex = 3, -- fallback caso o osso nominal falhe
        AttachOffset = { x = 0.0, y = 1.2, z = -0.42, rx = 0.0, ry = 0.0, rz = 0.0 },
        DeployOffset = { x = 0.0, y = -7.0, z = 0.0 },
        SpawnOffset = { x = 0.0, y = -10.5, z = 0.0 },
        InteractionRadiusFoot = 3.0,
        InteractionRadiusVehicle = 5.5,
        MaxLiftTolerance = 0.35,
    },

    -- Configuração do Handler de Contêineres
    Handler = {
        VehicleModel = 'handler',
        CraneBone = 'frame_2',
        AttachOffset = { x = 0.0, y = 1.78, z = -2.5, rx = 0.0, ry = 0.0, rz = 90.0 },
        InteractionRadius = 6.0,
    },

    -- Calibração de Carretas Compatíveis com Paletes Físicos
    CompatibleTrailers = {
        ['trailers2'] = {
            maxPallets = 8,
            length = 10.5,
            width = 2.6,
            renderLoadedPallets = true,
            attachOffsets = {
                { x = -0.55, y =  3.6, z = -0.90, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y =  3.6, z = -0.90, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.55, y =  1.2, z = -0.90, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y =  1.2, z = -0.90, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.55, y = -1.2, z = -0.90, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y = -1.2, z = -0.90, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.55, y = -3.6, z = -0.90, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y = -3.6, z = -0.90, rx = 0.0, ry = 0.0, rz = 0.0 },
            }
        },
        ['trailers'] = {
            maxPallets = 8,
            length = 10.5,
            width = 2.6,
            renderLoadedPallets = true,
            attachOffsets = {
                { x = -0.55, y =  3.6, z = -0.85, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y =  3.6, z = -0.85, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.55, y =  1.2, z = -0.85, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y =  1.2, z = -0.85, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.55, y = -1.2, z = -0.85, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y = -1.2, z = -0.85, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.55, y = -3.6, z = -0.85, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y = -3.6, z = -0.85, rx = 0.0, ry = 0.0, rz = 0.0 },
            }
        },
        ['freighttrailer'] = {
            maxPallets = 6,
            length = 10.0,
            width = 2.5,
            renderLoadedPallets = true,
            attachOffsets = {
                { x = -0.55, y =  2.8, z = 0.28, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y =  2.8, z = 0.28, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.55, y =  0.0, z = 0.28, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y =  0.0, z = 0.28, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.55, y = -2.8, z = 0.28, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y = -2.8, z = 0.28, rx = 0.0, ry = 0.0, rz = 0.0 },
            }
        },
        ['trflat'] = {
            maxPallets = 6,
            length = 10.0,
            width = 2.5,
            renderLoadedPallets = true,
            attachOffsets = {
                { x = -0.55, y =  2.8, z = 0.35, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y =  2.8, z = 0.35, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.55, y =  0.0, z = 0.35, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y =  0.0, z = 0.35, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.55, y = -2.8, z = 0.35, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.55, y = -2.8, z = 0.35, rx = 0.0, ry = 0.0, rz = 0.0 },
            }
        },
        ['docktrailer'] = {
            maxPallets = 4,
            length = 11.0,
            width = 2.6,
            renderLoadedPallets = true,
            attachOffsets = {
                { x = 0.0, y =  3.0, z = 1.20, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = 0.0, y =  1.0, z = 1.20, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = 0.0, y = -1.0, z = 1.20, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = 0.0, y = -3.0, z = 1.20, rx = 0.0, ry = 0.0, rz = 0.0 },
            }
        },
        ['mule'] = {
            maxPallets = 4,
            length = 6.0,
            width = 2.2,
            renderLoadedPallets = true,
            attachOffsets = {
                { x = -0.45, y = -1.5, z = 0.10, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.45, y = -1.5, z = 0.10, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x = -0.45, y = -3.2, z = 0.10, rx = 0.0, ry = 0.0, rz = 0.0 },
                { x =  0.45, y = -3.2, z = 0.10, rx = 0.0, ry = 0.0, rz = 0.0 },
            }
        }
    },

    -- ETAPA 2: Itens de Inspeção Obrigatória de Segurança no Veículo
    Inspection = {
        Duration = 3000,
        Animation = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
        Checkpoints = {
            { id = 'tire_front_left',  label = 'Inspecionar Pneu Dianteiro Esquerdo', offset = vector3(-1.2, 2.2, -0.4) },
            { id = 'tire_front_right', label = 'Inspecionar Pneu Dianteiro Direito',  offset = vector3(1.2, 2.2, -0.4) },
            { id = 'tire_rear_left',   label = 'Inspecionar Pneu Traseiro Esquerdo',  offset = vector3(-1.2, -2.2, -0.4) },
            { id = 'tire_rear_right',  label = 'Inspecionar Pneu Traseiro Direito',   offset = vector3(1.2, -2.2, -0.4) },
            { id = 'engine_hood',      label = 'Conferir Nível de Óleo e Motor',     offset = vector3(0.0, 2.8, 0.2) },
        }
    },

    -- ETAPA 4: Fixação de Cintas e Assinatura de Romaneio
    Strapping = {
        Duration = 4500,
        Animation = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle' },
        Label = 'Fixar Cintas de Carga e Assinar Romaneio',
        RearOffset = vector3(0.0, -4.8, 0.2)
    },

    -- Destinos de Entrega (Polarix Sample Destinations)
    DeliveryDestinations = {
        [1] = {
            id = 'dest_paleto',
            label = 'Paleto Bay Main Depot',
            coords = vector4(89.08, 6334.58, 31.23, 120.0),
            unloadingPoint = vector3(82.5, 6340.2, 31.23),
            reward = 7500,
            xp = 250
        },
        [2] = {
            id = 'dest_senora',
            label = 'Grand Senora Desert Depot',
            coords = vector4(1968.90, 3751.97, 32.20, 211.27),
            unloadingPoint = vector3(1960.0, 3755.0, 32.20),
            reward = 6200,
            xp = 200
        },
        [3] = {
            id = 'dest_lamesa',
            label = 'La Mesa Industrial',
            coords = vector4(919.49, -1563.58, 30.76, 90.16),
            unloadingPoint = vector3(915.0, -1570.0, 30.76),
            reward = 4800,
            xp = 180
        },
        [4] = {
            id = 'dest_lsia',
            label = 'LSIA Freight Yard',
            coords = vector4(-892.51, -2740.97, 13.83, 338.75),
            unloadingPoint = vector3(-885.0, -2745.0, 13.83),
            reward = 5200,
            xp = 190
        }
    }
}

-- =======================================================================
-- SISTEMA MULTI-CARGAS: DEFINIÇÕES DE CARGA COM PROGRESSÃO POR TIERS
-- =======================================================================
Config.CargoTypes = {
    manual_boxes = {
        label = 'Tier 1: Carga Manual (Caixas Fracionadas)',
        minLevel = 1,
        allowedTrailers = {
            joaat('boxville'),
            joaat('boxville2'),
            joaat('mule'),
            joaat('mule2'),
            joaat('benson'),
            joaat('trflat'),
            joaat('freighttrailer'),
        },
        allowedTrucks = {
            joaat('benson'),
            joaat('mule'),
            joaat('hauler'),
            joaat('hauler2'),
            joaat('packer'),
            joaat('phantom'),
        },
        defaultTrailer = 'trflat',
        defaultTruck = 'benson',
        boxCount = 6,
        boxModel = 'prop_cardbordbox_02a',
    },
    pallet_jack = {
        label = 'Tier 2: Carga com Paleteira Manual (Lotes Médios)',
        minLevel = 3,
        allowedTrailers = {
            joaat('freighttrailer'),
            joaat('trflat'),
            joaat('mule'),
            joaat('benson'),
        },
        allowedTrucks = {
            joaat('benson'),
            joaat('mule'),
            joaat('hauler'),
            joaat('hauler2'),
            joaat('packer'),
            joaat('phantom'),
        },
        defaultTrailer = 'trflat',
        defaultTruck = 'hauler',
        batchCount = 4,
        jackModel = 'prop_pallet_jack_01',
    },
    dry = {
        label = 'Tier 3: Carga Seca Industrial (Paletes & Empilhadeira)',
        minLevel = 5,
        allowedTrailers = {
            joaat('freighttrailer'),
            joaat('trflat'),
        },
        allowedTrucks = {
            joaat('hauler'),
            joaat('hauler2'),
            joaat('packer'),
            joaat('phantom'),
            joaat('phantom3'),
            joaat('biff'),
        },
        defaultTrailer = 'trflat',
        forkliftModel = 'forklift',
    },
    liquid = {
        label = 'Carga Líquida (Tanque / Combustível)',
        minLevel = 7,
        allowedTrailers = {
            joaat('tanker'),
            joaat('tanker2'),
            joaat('armytanker'),
        },
        allowedTrucks = {
            joaat('hauler'),
            joaat('hauler2'),
            joaat('packer'),
            joaat('phantom'),
            joaat('phantom3'),
        },
        defaultTrailer = 'tanker',
        fuelTerminals = {
            {
                id = 'buccaneer_pump_1',
                name = 'Bomba 01 — Terminal Portuário Buccaneer',
                coords = vector3(1272.50, -3168.20, 5.90),
                pumpCoords = vector4(1272.50, -3168.20, 5.90, 90.0),
                propModel = 'prop_gas_pump_1d',
                hoseModel = 'prop_cs_fuel_nozle',
                radius = 2.5
            },
            {
                id = 'murrieta_refinery_pump',
                name = 'Bomba 02 — Refinaria El Burro Heights',
                coords = vector3(2732.10, 1475.20, 24.50),
                pumpCoords = vector4(2732.10, 1475.20, 24.50, 0.0),
                propModel = 'prop_gas_pump_1d',
                hoseModel = 'prop_cs_fuel_nozle',
                radius = 2.5
            },
            {
                id = 'paleto_fuel_depot',
                name = 'Bomba 03 — Depósito Paleto Bay',
                coords = vector3(170.15, 6429.50, 31.40),
                pumpCoords = vector4(170.15, 6429.50, 31.40, 45.0),
                propModel = 'prop_gas_pump_1d',
                hoseModel = 'prop_cs_fuel_nozle',
                radius = 2.5
            }
        },
        tankerAttachOffset = vector3(-1.45, -2.5, 0.5),
        fillDuration = 12000,
        maxDistance = 9.0,
        leakPenalty = 1500,
    },
    container = {
        label = 'Tier 4: Carga Pesada (Contêiner Heavy Lift & Reach Stacker)',
        minLevel = 10,
        allowedTrailers = {
            joaat('trflat'),
        },
        allowedTrucks = {
            joaat('hauler'),
            joaat('hauler2'),
            joaat('packer'),
            joaat('phantom'),
            joaat('phantom3'),
        },
        defaultTrailer = 'trflat',
        handlerModel = 'handler',
        containerModel = 'prop_contr_03b_ld',
        handlerAttachOffset = vector3(0.0, 1.78, -2.5),
        trailerAttachOffset = vector3(0.0, -1.8, 1.35),
        twistlocks = {
            { id = 1, label = 'Trava Dianteira Esquerda', offset = vector3(-1.1, 3.2, 0.45) },
            { id = 2, label = 'Trava Dianteira Direita',  offset = vector3(1.1, 3.2, 0.45) },
            { id = 3, label = 'Trava Traseira Esquerda',   offset = vector3(-1.1, -4.5, 0.45) },
            { id = 4, label = 'Trava Traseira Direita',    offset = vector3(1.1, -4.5, 0.45) },
        }
    },
    illegal = {
        label = 'Tier 5: Mercado Ilegal (Carga Clandestina & Perseguição Policial)',
        minLevel = 15,
        allowedTrailers = {
            joaat('freighttrailer'),
            joaat('trailers2'),
            joaat('trflat'),
        },
        allowedTrucks = {
            joaat('hauler'),
            joaat('hauler2'),
            joaat('packer'),
            joaat('phantom'),
            joaat('phantom3'),
            joaat('biff'),
        },
        defaultTrailer = 'freighttrailer',
        nightHours = { start = 22, finish = 4 },
        rewardMultiplier = 2.5,
        heatReward = 15,
        heatThresholdPursuit = 50,
        washCleanCostPerHeat = 250,
    }
}

Config.ForkliftAttachOffset = vector3(0.0, 1.2, -0.42)

-- =======================================================================
-- MÓDULO 1: SISTEMA DE INTEGRIDADE DA CARGA E DESGASTE MECÂNICO
-- =======================================================================
Config.CargoHealth = {
    InitialHealth = 100,
    TireBurstChanceOnCriticalImpact = 0.30,
    CriticalImpactHealthDelta = 35.0,
    DamageMultiplier = 0.45,
    RepairSkillCheck = { 'easy', 'medium', 'easy' },
}

Config.ContainerSpawnCoord = vector4(1230.50, -3183.20, 5.00, 90.0)

-- =======================================================================
-- FASE 2: MÓDULO 1 - SISTEMA MULTIPLAYER CO-OP (CREW / LOGÍSTICA EM EQUIPE)
-- =======================================================================
Config.Crew = {
    MaxMembers = 4,
    InviteDistance = 20.0,
    SharedPayoutBonusPercent = 0.15, -- 15% de bônus cooperativo total distribuído
}

-- =======================================================================
-- FASE 2: MÓDULO 2 - SISTEMA TYCOON (BASES / GARAGENS PERSISTENTES)
-- =======================================================================
Config.TycoonBases = {
    ['base_sandy'] = {
        id = 'base_sandy',
        label = 'Base Logística Grand Senora',
        price = 120000,
        coords = vector3(1705.20, 3286.40, 41.10),
        workshopCoords = vector3(1712.10, 3290.50, 41.10),
        fuelDiscount = 0.25,   -- 25% de desconto em combustível
        repairDiscount = 0.40, -- 40% de desconto em oficina
        blip = { sprite = 357, color = 5, scale = 0.85 }
    },
    ['base_paleto'] = {
        id = 'base_paleto',
        label = 'Terminal de Cargas Paleto Bay',
        price = 180000,
        coords = vector3(154.50, 6386.20, 31.30),
        workshopCoords = vector3(160.20, 6395.10, 31.30),
        fuelDiscount = 0.30,
        repairDiscount = 0.45,
        blip = { sprite = 357, color = 5, scale = 0.85 }
    },
    ['base_elysian'] = {
        id = 'base_elysian',
        label = 'Depósito Industrial Elysian Island',
        price = 250000,
        coords = vector3(290.10, -3015.40, 5.80),
        workshopCoords = vector3(282.40, -3005.10, 5.80),
        fuelDiscount = 0.35,
        repairDiscount = 0.50,
        blip = { sprite = 357, color = 5, scale = 0.85 }
    }
}

-- =======================================================================
-- FASE 2: MÓDULO 2 - OFICINA PRIVADA (WORKSHOP UPGRADES DE FROTA)
-- =======================================================================
Config.WorkshopUpgrades = {
    RepairBaseCost = 1500, -- Custo base de reparo completo (reduzido pela posse da base)
    Engine = {
        [1] = { level = 1, mod = 11, label = 'Motor Preparado Nível 1', price = 8000 },
        [2] = { level = 2, mod = 11, label = 'Motor Preparado Nível 2', price = 16000 },
        [3] = { level = 3, mod = 11, label = 'Motor de Alta Performance Nível 3', price = 28000 },
    },
    Brakes = {
        [1] = { level = 1, mod = 12, label = 'Freios Hidráulicos Nível 1', price = 5000 },
        [2] = { level = 2, mod = 12, label = 'Freios Reforçados Nível 2', price = 11000 },
    },
    Transmission = {
        [1] = { level = 1, mod = 13, label = 'Câmbio Escalonado Nível 1', price = 7000 },
        [2] = { level = 2, mod = 13, label = 'Transmissão Esportiva Pesada Nível 2', price = 15000 },
    },
    Armor = {
        [1] = { level = 1, mod = 16, label = 'Blindagem e Reforço de Chassi 50%', price = 12000 },
        [2] = { level = 2, mod = 16, label = 'Blindagem e Reforço Estrutural 100%', price = 24000 },
    }
}

-- =======================================================================
-- FASE 2: MÓDULO 3 - TIERS INICIAIS (EARLY GAME: CAIXAS & PALETEIRA MANUAL)
-- =======================================================================
Config.EarlyGame = {
    Boxes = {
        PropModel = 'prop_cardbordbox_02a',
        Anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },
        AttachBone = 60309, -- SKEL_R_Hand
        AttachOffset = vector3(0.08, 0.08, 0.0),
        AttachRot = vector3(-90.0, 0.0, 0.0),
        LoadingStaging = vector3(1243.50, -3168.20, 5.50), -- Pilha de caixas no pátio
    },
    PalletJack = {
        PropModel = 'prop_pallet_jack_01',
        AttachOffset = vector3(0.0, 1.25, -0.65),
        AttachRot = vector3(0.0, 0.0, 180.0),
        SpeedBonus = 1.35, -- Caminhada mais ágil comparada ao carregamento manual
    }
}

