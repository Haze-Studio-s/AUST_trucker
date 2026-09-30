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
-- SISTEMA MULTI-CARGAS: DEFINIÇÕES DE CARGA SECA E LÍQUIDA
-- =======================================================================
Config.CargoTypes = {
    dry = {
        label = 'Carga Seca (Paletes)',
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
        tankerAttachOffset = vector3(-1.45, -2.5, 0.5), -- Engate lateral da mangueira
        fillDuration = 12000, -- 12 segundos para encher 100%
        maxDistance = 9.0, -- Distância máxima entre o jogador e o caminhão-tanque durante o enchimento
        leakPenalty = 1500, -- Penalidade financeira se o jogador abandonar/romper a mangueira
    },
    container = {
        label = 'Carga Pesada (Contêiner Industrial)',
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
        label = 'Mercado Ilegal (Carga Clandestina)',
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
        washCleanCostPerHeat = 250, -- Custo por ponto de heat em dinheiro sujo
    }
}

Config.ForkliftAttachOffset = vector3(0.0, 1.2, -0.42) -- Eixo Z rebaixado para assentar perfeitamente sobre as lâminas

-- =======================================================================
-- MÓDULO 1: SISTEMA DE INTEGRIDADE DA CARGA E DESGASTE MECÂNICO
-- =======================================================================
Config.CargoHealth = {
    InitialHealth = 100,
    TireBurstChanceOnCriticalImpact = 0.30, -- 30% de chance de estourar pneu
    CriticalImpactHealthDelta = 35.0,      -- Queda brusca de integridade corporal para impacto crítico
    DamageMultiplier = 0.45,               -- Fator de conversão de dano do caminhão para a carga
    RepairSkillCheck = { 'easy', 'medium', 'easy' },
}

-- Posição padrão de contêiner aguardando içamento no pátio
Config.ContainerSpawnCoord = vector4(1230.50, -3183.20, 5.00, 90.0)
