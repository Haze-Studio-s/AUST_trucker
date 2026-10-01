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

    -- Props de Paletes Oficiais de Carga (Carrier Cargo Heist)
    PalletProps = {
        'hei_prop_carrier_cargo_04b',
    },
    PalletModels = {
        'hei_prop_carrier_cargo_04b',
    },

    DefaultPalletModel = 'hei_prop_carrier_cargo_04b',
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
        LoadingBayCoords = vector4(1244.53, -3135.57, 4.53, 90.0),
        PalletStagingAnchor = vector3(1272.00, -3182.00, 5.90),
        PalletStagingHeading = 180.0,
    },

    LoadingBayCoords = vector4(1244.53, -3135.57, 4.53, 90.0),
    PalletProps = {
        'hei_prop_carrier_cargo_04b',
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
    vehicle_carrier = {
        label = 'Transporte de Veículos (Cegonha Car Carrier)',
        allowedTrailers = {
            joaat('tr2'),
        },
        allowedTrucks = {
            joaat('hauler'),
            joaat('hauler2'),
            joaat('packer'),
            joaat('phantom'),
            joaat('phantom3'),
        },
        defaultTrailer = 'tr2',
        carModels = { 'elegy2', 'jester', 'comet2' },
        yard = {
            stagingCoords = {
                vector4(1235.0, -3150.0, 4.6, 90.0),
                vector4(1235.0, -3155.0, 4.6, 90.0),
                vector4(1235.0, -3160.0, 4.6, 90.0),
            }
        }
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
    heavy = {
        label = 'Carga Pesada (Contêiner / Reach Stacker)',
        allowedTrailers = {
            joaat('docktrailer'),
            joaat('trailers2'),
            joaat('trflat'),
        },
        allowedTrucks = {
            joaat('hauler'),
            joaat('hauler2'),
            joaat('packer'),
            joaat('phantom'),
            joaat('phantom3'),
        },
        defaultTrailer = 'docktrailer',
        handlerModel = 'handler',
        containerModel = 'prop_contr_03b_ld',
        yard = {
            dispatcher = vector4(1181.23, -3113.83, 6.03, 90.0),
            truckSpawns = {
                vector4(1245.79, -3155.76, 4.6, 90.0),
                vector4(1245.09, -3142.37, 4.55, 90.0),
            },
            trailerSpawns = {
                vector4(1272.21, -3159.80, 4.90, 90.0),
                vector4(1274.77, -3169.75, 4.90, 90.0),
            },
            handlerSpawns = {
                vector4(1130.11, -3083.45, 6.01, 269.29),
                vector4(1135.20, -3090.10, 6.01, 269.29),
            },
            containerSpawns = {
                vector4(1178.15, -3115.13, 5.02, 266.0),
                vector4(1247.42, -3118.35, 7.71, 91.2),
                vector4(1275.52, -3241.56, 4.90, 181.9),
                vector4(1055.81, -3048.53, 4.90, 176.5),
            }
        }
    },
    adr = {
        label = 'Carga Perigosa (ADR / Químicos & Inflamáveis)',
        allowedTrailers = {
            joaat('tanker'),
            joaat('tanker2'),
            joaat('armytanker'),
            joaat('freighttrailer'),
        },
        allowedTrucks = {
            joaat('hauler'),
            joaat('hauler2'),
            joaat('packer'),
            joaat('phantom'),
            joaat('phantom3'),
        },
        defaultTrailer = 'tanker',
        leakThresholdSpeed = 58.0,
        leakThresholdSteer = 16.0,
        leakDecayRate = 2,
    }
}

-- =======================================================================
-- SISTEMA DE LICENÇAS TÉCNICAS E EXAMES
-- =======================================================================
Config.Licenses = {
    adr = {
        name = 'Certificação ADR Specialist',
        minLevel = 3,
        examFee = 1500,
        description = 'Habilita o transporte de substâncias inflamáveis, gases pressurizados e materiais químicos perigosos.',
        questions = {
            {
                q = 'Qual o procedimento padrão ao notar vazamento em válvula de alívio de carga inflamável?',
                options = {
                    'Parar imediatamente o comboio em local seguro e acionar a válvula de contenção manual',
                    'Acelerar para terminar o frete antes que o tanque esvazie completamente',
                    'Despejar água comum sobre a fiação do motor sem desligar o veículo'
                },
                correct = 1
            },
            {
                q = 'Qual a velocidade máxima recomendada para curvas fechadas transportando tanques de combustível?',
                options = {
                    'Acima de 80 km/h para manter estabilidade centrífuga',
                    'Abaixo de 50 km/h com redução gradual prévia para evitar tombamento',
                    'A velocidade não interfere no centro de gravidade de carretas tanque'
                },
                correct = 2
            }
        }
    },
    heavy = {
        name = 'Certificação Heavy Lift Operator',
        minLevel = 2,
        examFee = 1000,
        description = 'Habilita o manuseio de Reach Stackers e transporte rodoviário de contêineres marítimos pesados.',
        questions = {
            {
                q = 'O que deve ser verificado antes de erguer um contêiner com o spreader do Reach Stacker?',
                options = {
                    'Alinhamento dos 4 cantos de travamento eletromagnético (twistlocks)',
                    'Buzinar três vezes e puxar o freio de mão em movimento',
                    'Içar com a torre inclinada para frente para acelerar a carga'
                },
                correct = 1
            }
        }
    }
}

Config.ForkliftAttachOffset = vector3(0.0, 1.2, -0.42) -- Eixo Z rebaixado para assentar perfeitamente sobre as lâminas

-- =======================================================================
-- SISTEMA DE SLOTS FIXOS COM GHOST PREVIEW (Padrão 0r-trucker / Polarix)
-- =======================================================================
Config.TrailerSlots = {
    ['trflat'] = {
        deckZ = 0.35,
        pallets = {
            vector3(-0.55,  3.6, 0.35), vector3( 0.55,  3.6, 0.35), -- Frente (slots 1 e 2)
            vector3(-0.55,  1.2, 0.35), vector3( 0.55,  1.2, 0.35), -- Meio-Frente (slots 3 e 4)
            vector3(-0.55, -1.2, 0.35), vector3( 0.55, -1.2, 0.35), -- Meio-Trás (slots 5 e 6)
            vector3(-0.55, -3.6, 0.35), vector3( 0.55, -3.6, 0.35), -- Traseira (slots 7 e 8)
        },
        forklift = vector3(0.0, -5.2, 0.35)
    },
    ['freighttrailer'] = {
        deckZ = 0.35,
        pallets = {
            vector3(-0.55,  3.6, 0.35), vector3( 0.55,  3.6, 0.35),
            vector3(-0.55,  1.2, 0.35), vector3( 0.55,  1.2, 0.35),
            vector3(-0.55, -1.2, 0.35), vector3( 0.55, -1.2, 0.35),
            vector3(-0.55, -3.6, 0.35), vector3( 0.55, -3.6, 0.35),
        },
        forklift = vector3(0.0, -5.4, 0.35)
    },
    ['trailers2'] = {
        deckZ = 0.35,
        pallets = {
            vector3(-0.55,  4.8, 0.35), vector3( 0.55,  4.8, 0.35),
            vector3(-0.55,  2.8, 0.35), vector3( 0.55,  2.8, 0.35),
            vector3(-0.55,  0.8, 0.35), vector3( 0.55,  0.8, 0.35),
            vector3(-0.55, -1.2, 0.35), vector3( 0.55, -1.2, 0.35),
            vector3(-0.55, -3.2, 0.35), vector3( 0.55, -3.2, 0.35),
            vector3(-0.55, -5.0, 0.35), vector3( 0.55, -5.0, 0.35),
        },
        forklift = vector3(0.0, -6.6, 0.35)
    },
    ['trailers'] = {
        deckZ = 0.35,
        pallets = {
            vector3(-0.55,  4.8, 0.35), vector3( 0.55,  4.8, 0.35),
            vector3(-0.55,  2.8, 0.35), vector3( 0.55,  2.8, 0.35),
            vector3(-0.55,  0.8, 0.35), vector3( 0.55,  0.8, 0.35),
            vector3(-0.55, -1.2, 0.35), vector3( 0.55, -1.2, 0.35),
            vector3(-0.55, -3.2, 0.35), vector3( 0.55, -3.2, 0.35),
            vector3(-0.55, -5.0, 0.35), vector3( 0.55, -5.0, 0.35),
        },
        forklift = vector3(0.0, -6.6, 0.35)
    },
    ['docktrailer'] = {
        deckZ = 0.35,
        pallets = {
            vector3(-0.55,  3.6, 0.35), vector3( 0.55,  3.6, 0.35),
            vector3(-0.55,  1.2, 0.35), vector3( 0.55,  1.2, 0.35),
            vector3(-0.55, -1.2, 0.35), vector3( 0.55, -1.2, 0.35),
            vector3(-0.55, -3.6, 0.35), vector3( 0.55, -3.6, 0.35),
        },
        forklift = vector3(0.0, -5.4, 0.35)
    }
}
