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

    -- Modelos de Paletes Oficiais do Polarix e Base GTA
    PalletModels = {
        'ex_prop_crate_tob_sc',
        'prop_boxpile_06a',
        'prop_boxpile_07d',
        'prop_boxpile_02b',
        'prop_pallet_01a',
        'prop_contr_03b_ld',
        'sm3d_prop_pallet_1', -- Suporte nativo ao custom stream se presente
    },

    DefaultPalletModel = 'prop_boxpile_06a',
    ContainerModel = 'prop_contr_03b_ld',

    PalletWeightKg = 1000,
    MaxPalletsPerOrder = 8,

    -- Coordenadas de Referência do Pátio e Docas (Polarix / Buccaneer)
    Warehouse = {
        Dispatcher = vector4(1268.50, -3175.20, 5.91, 180.00),
        YardManagerPed = 's_m_m_dockwork_01',
        TruckSpawnCoords = vector4(1250.55, -3162.40, 5.88, 270.00),
        TrailerSpawnCoords = vector4(1239.50, -3162.40, 5.88, 270.00),
        ForkliftBayCoords = vector4(1253.20, -3180.10, 5.88, 270.00),
        HandlerBayCoords = vector4(1240.20, -3195.10, 5.88, 270.00),
        PalletStagingAnchor = vector3(1272.00, -3182.00, 5.90),
        PalletStagingHeading = 180.0,
    },

    -- Configuração e Offsets de Empilhadeira (Forklift) - Extraído do Polarix
    Forklift = {
        VehicleModel = 'forklift',
        AttachBone = 'forks_attach',
        ForkBoneIndex = 3, -- fallback caso o osso nominal falhe
        AttachOffset = { x = 0.0, y = 1.25, z = -0.15, rx = 0.0, ry = 0.0, rz = 0.0 },
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
            joaat('trailers2'),
            joaat('trailers'),
            joaat('trflat'),
            joaat('docktrailer'),
            joaat('mule'),
            joaat('mule2'),
            joaat('mule3'),
            joaat('mule4'),
            joaat('pounder'),
            joaat('pounder2'),
        },
        allowedTrucks = {
            joaat('hauler'),
            joaat('hauler2'),
            joaat('packer'),
            joaat('phantom'),
            joaat('phantom3'),
            joaat('biff'),
        },
        defaultTrailer = 'trailers2',
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
    }
}
