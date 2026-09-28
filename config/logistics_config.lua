-- ============================================================
-- AUST_trucker — config/logistics_config.lua
-- Transplante completo das configurações do lc_truck_logistics
-- ============================================================

Config = Config or {}

-- Contratos e Cargas do Mercado de Frete & Trabalhos Rápidos
Config.LC_Jobs = {
    cancel_job_key = 167, -- F6
    inspect_cargo_time = 5,

    contract_generation = {
        cooldown = 5,
        contracts_per_interval = 5,
        max_active_contracts = 30,
        max_illegal_contracts = 5,
    },

    economy = {
        price_per_km = {
            min = 1000,
            max = 1600,
        },
        multipliers = {
            freight = 1.2,
            illegal = 1.8,
        }
    },

    special_cargo = {
        urgent = {
            chance_percent = 15,
            seconds_per_km = 90,
            reward_penalty_percent = 20,
        },
        fragile = {
            min_health_percent = 70,
            reward_penalty_percent = 20,
        }
    },

    truck_rental = {
        available_trucks = { "hauler", "packer", "blacktop", "brickades", "vetirs" },
        must_return_truck = true,
        rental_fee_percent = 15,
    },

    available_loads = {
        -- def = { ADR (0-6), Fragile (0-1), Valuable (0-1), Illegal (0-1) }
        { trailer = "armytanker", name = "Tanque Combustível Militar", def = {3,0,0,0} },
        { trailer = "armytanker", name = "Suprimento de Água Militar", def = {0,0,0,0} },
        { trailer = "armytanker", name = "Tanque de Materiais Corrosivos", def = {6,0,1,0} },
        { trailer = "armytanker", name = "Tanque de Gás Inflamável", def = {2,0,0,0} },
        { trailer = "armytanker", name = "Tanque de Gás Tóxico", def = {5,0,0,0} },
        { trailer = "armytanker", name = "Materiais Secretos do Exército", def = {0,0,1,0} },

        { trailer = "docktrailer", name = "Transporte de Móveis", def = {0,0,0,0} },
        { trailer = "docktrailer", name = "Transporte de Geladeiras", def = {0,1,0,0} },
        { trailer = "docktrailer", name = "Transporte de Tijolos", def = {0,0,0,0} },
        { trailer = "docktrailer", name = "Produtos Importados", def = {0,0,1,0} },
        { trailer = "docktrailer", name = "Carga de Plásticos", def = {0,0,0,0} },
        { trailer = "docktrailer", name = "Transporte de Vestuário", def = {0,0,0,0} },
        { trailer = "docktrailer", name = "Transporte de Eletrodomésticos", def = {0,0,0,0} },
        { trailer = "docktrailer", name = "Produtos de Limpeza", def = {0,0,0,0} },
        { trailer = "docktrailer", name = "Madeira Nobre Refinada", def = {0,0,0,0} },
        { trailer = "docktrailer", name = "Transporte de Minérios e Pedras", def = {0,0,0,0} },
        { trailer = "docktrailer", name = "Carga de Joias e Diamantes", def = {0,1,1,0} },
        { trailer = "docktrailer", name = "Transporte de Painéis de Vidro", def = {0,1,0,0} },
        { trailer = "docktrailer", name = "Munições e Armamentos Leves", def = {1,0,0,0} },

        { trailer = "tr2", name = "Cegonheira com Veículos", def = {0,1,1,0} },
        { trailer = "trailers4", name = "Artigos Navais e Barcos", def = {0,1,1,0} },
        { trailer = "tr4", name = "Transporte de Veículos Importados", def = {0,1,1,0} },
        { trailer = "tvtrailer", name = "Equipamentos para Grandes Shows", def = {0,0,1,0} },

        { trailer = "tanker", name = "Tanque de Combustível Aditivado", def = {3,0,0,0} },
        { trailer = "tanker2", name = "Tanque de Querosene de Aviação", def = {3,0,0,0} },
        { trailer = "tanker2", name = "Tanque de Óleo Diesel Pesado", def = {3,0,0,0} },

        { trailer = "trailerlogs", name = "Transporte de Toras de Madeira", def = {0,0,0,0} },

        { trailer = "trailers", name = "Materiais de Construção Civil", def = {0,0,0,0} },
        { trailer = "trailers", name = "Carga de Borracha Industrial", def = {0,0,0,0} },
        { trailer = "trailers", name = "Vacinas e Insumos Hospitalares", def = {0,1,0,0} },
        { trailer = "trailers", name = "Carga de Explosivos Industriais", def = {1,1,0,0} },

        { trailer = "trailers2", name = "Carnes Nobres Congeladas", def = {0,0,0,0} },
        { trailer = "trailers2", name = "Laticínios e Leite Pasteurizado", def = {0,0,0,0} },
        { trailer = "trailers2", name = "Alimentos Enlatados em Conserva", def = {0,0,0,0} },
        { trailer = "trailers2", name = "Queijos Artesanais e Vinhos", def = {0,0,0,0} },

        { trailer = "trailers3", name = "Pisos e Revestimentos Cerâmicos", def = {0,1,0,0} },
        { trailer = "trailers3", name = "Trilhos Ferroviários de Aço", def = {0,0,0,0} },

        { trailer = "trailers4", name = "Fogos de Artifício", def = {1,1,0,0} },
        { trailer = "trailers4", name = "Dinamites para Mineração", def = {1,1,0,0} },
        { trailer = "trailers4", name = "Fósforo Branco", def = {4,1,0,0} },

        -- Cargas Ilegais / Contrabando (Requer Habilidade Ilegal)
        { trailer = "docktrailer", name = "Carga de Marfim Contrabandeado", def = {0,1,1,1} },
        { trailer = "tanker", name = "Solvente Químico Não Autorizado", def = {6,1,1,1} },
        { trailer = "trailers2", name = "Animais Silvestres Exóticos", def = {0,1,1,1} },
        { trailer = "trailers3", name = "Remédios Tarja Preta do Mercado Negro", def = {5,1,1,1} },
        { trailer = "trailers4", name = "Bebidas Alcoólicas Destiladas Ilegalmente", def = {3,0,0,1} },
    }
}

-- Concessionária de Caminhões (Dealership)
Config.LC_SellMultiplier = 0.70 -- 70% de retorno na venda
Config.LC_Dealership = {
    ['vetirs'] = {
        name = 'Vetir Semi',
        price = 25000,
        engine = "10.0L Vetir I6",
        transmission = "5-Speed",
        hp = '380',
        img = 'img/trucks/vetirs.png',
        driver_bonus = 1,
        required_level = 0
    },
    ['blacktop'] = {
        name = 'Brute Blacktop',
        price = 45000,
        engine = "11.0L Brute I6",
        transmission = "6-Speed",
        hp = '420',
        img = 'img/trucks/blacktop.png',
        driver_bonus = 2,
        required_level = 4
    },
    ['brickades'] = {
        name = 'MTL Brickade',
        price = 60000,
        engine = "12.5L Turbocharged V8",
        transmission = "8-Speed",
        hp = '480',
        img = 'img/trucks/brickades.png',
        driver_bonus = 4,
        required_level = 10
    },
    ['hauler'] = {
        name = 'JoBuilt Hauler',
        price = 70000,
        engine = "12.0L Turbocharged V8",
        transmission = "8-Speed",
        hp = '500',
        img = 'img/trucks/hauler.png',
        driver_bonus = 4,
        required_level = 12
    },
    ['aerocab'] = {
        name = 'Vapid Tanker',
        price = 90000,
        engine = "12.5L Turbocharged V8",
        transmission = "8-Speed",
        hp = '565',
        img = 'img/trucks/aerocab.png',
        driver_bonus = 6,
        required_level = 16
    },
    ['linerunner'] = {
        name = 'HVY Linerunner',
        price = 105000,
        engine = "14.0L Supercharged V10",
        transmission = "10-Speed",
        hp = '580',
        img = 'img/trucks/linerunner.png',
        driver_bonus = 6,
        required_level = 18
    },
    ['packer'] = {
        name = 'MTL Packer',
        price = 110000,
        engine = "13.0L Supercharged V8",
        transmission = "8-Speed",
        hp = '570',
        img = 'img/trucks/packer.png',
        driver_bonus = 6,
        required_level = 20
    },
    ['phantom'] = {
        name = 'JoBuilt Phantom',
        price = 130000,
        engine = "15.0L Turbocharged V12",
        transmission = "10-Speed",
        hp = '600',
        img = 'img/trucks/phantom.png',
        driver_bonus = 8,
        required_level = 24
    },
    ['phantom3'] = {
        name = 'JoBuilt Phantom Custom',
        price = 180000,
        engine = "16.5L Twin-Turbo V16",
        transmission = "12-Speed Plus",
        hp = '650',
        img = 'img/trucks/phantom3.png',
        driver_bonus = 10,
        required_level = 30
    }
}

-- Oficina e Desgaste Mecânico (Custo por 1% de dano)
Config.LC_RepairPrice = {
    engine = 75,
    body = 40,
    transmission = 50,
    wheels = 25,
    fuel = 5
}

-- Empréstimos Bancários Scaláveis
Config.LC_MaxLoanPerLevel = {
    [0]  = 40000,
    [10] = 100000,
    [20] = 250000,
    [30] = 600000
}

Config.LC_Loans = {
    payment_interval_hours = 24,
    plans = {
        { loan_amount = 20000,  interest_rate = 20.0, repayment_days = 15 },
        { loan_amount = 50000,  interest_rate = 17.5, repayment_days = 20 },
        { loan_amount = 100000, interest_rate = 15.0, repayment_days = 25 },
        { loan_amount = 400000, interest_rate = 12.5, repayment_days = 30 },
    }
}

-- Árvore de Competências (Skill Tree) & Especializações
Config.LC_DistanceSkill = {
    [0] = 6.0,
    [1] = 6.5,
    [2] = 7.0,
    [3] = 7.5,
    [4] = 8.0,
    [5] = 8.5,
    [6] = 99.0
}

Config.LC_ExpGain = 3.0 -- XP por km percorrido

Config.LC_Bonus = {
    distance = {
        money_bonus_percentage = { [1] = 2, [2] = 4, [3] = 6, [4] = 8, [5] = 10, [6] = 12 },
        exp_bonus_percentage   = { [1] = 5, [2] = 5, [3] = 5, [4] = 5, [5] = 10, [6] = 15 }
    },
    valuable = {
        money_bonus_percentage = { [1] = 2, [2] = 4, [3] = 6, [4] = 8, [5] = 10, [6] = 12 },
        exp_bonus_percentage   = { [1] = 10, [2] = 10, [3] = 10, [4] = 10, [5] = 10, [6] = 10 }
    },
    fragile = {
        money_bonus_percentage = { [1] = 2, [2] = 4, [3] = 6, [4] = 8, [5] = 10, [6] = 12 },
        exp_bonus_percentage   = { [1] = 10, [2] = 10, [3] = 10, [4] = 10, [5] = 10, [6] = 10 }
    },
    fast = {
        money_bonus_percentage = { [1] = 2, [2] = 4, [3] = 6, [4] = 8, [5] = 10, [6] = 12 },
        exp_bonus_percentage   = { [1] = 10, [2] = 10, [3] = 10, [4] = 10, [5] = 10, [6] = 10 }
    },
    illegal = {
        money_bonus_percentage = { [1] = 2, [2] = 4, [3] = 6, [4] = 8, [5] = 10, [6] = 12 },
        exp_bonus_percentage   = { [1] = 10, [2] = 10, [3] = 10, [4] = 10, [5] = 10, [6] = 10 }
    }
}

Config.LC_RequiredXP = {
    [1] = 1000, [2] = 1400, [3] = 1900, [4] = 2500, [5] = 3200, [6] = 4000,
    [7] = 4900, [8] = 5900, [9] = 7000, [10] = 8200, [11] = 9500, [12] = 10900,
    [13] = 12400, [14] = 14000, [15] = 15700, [16] = 17500, [17] = 19400, [18] = 21400,
    [19] = 23500, [20] = 25700, [21] = 28000, [22] = 30400, [23] = 32900, [24] = 35500,
    [25] = 38200, [26] = 41000, [27] = 43900, [28] = 46900, [29] = 50000, [30] = 53200,
    [31] = 56500, [32] = 59900, [33] = 63400, [34] = 67000, [35] = 70700, [36] = 100000,
}

-- Agência de Recrutamento & Motoristas NPC
Config.LC_Drivers = {
    cooldown = 20, -- min
    hiring_costs = {
        min = 500,
        max = 1000,
        percentage_skills = 25,
    },
    max_active_drivers = 20,
    max_drivers_per_player = {
        [0] = 1,
        [10] = 2,
        [20] = 3,
        [30] = 5
    }
}

Config.LC_DriverJobs = {
    cooldown = 30, -- minutos
    profit = {
        min = 250,
        max = 500,
        percentage_skills = 15,
    },
    fuel_consumption = {
        min = 2,
        max = 8
    },
    generate_money_offline = false
}

-- Pontos de Entrega Dinâmicos
Config.LC_DeliveryLocations = {
    vector4(-758.14, 5540.96, 33.49, 110.53),
    vector4(-3046.19, 143.27, 11.60, 11.14),
    vector4(-1153.01, 2672.99, 18.10, 312.25),
    vector4(622.67, 110.27, 92.59, 340.75),
    vector4(-574.62, -1147.27, 22.18, 177.70),
    vector4(376.31, 2638.97, 44.50, 286.38),
    vector4(1738.32, 3283.89, 41.13, 16.24),
    vector4(1419.98, 3618.63, 34.91, 195.33),
    vector4(1452.67, 6552.02, 14.89, 138.69),
    vector4(3472.40, 3681.97, 33.79, 76.44),
    vector4(2485.73, 4116.13, 38.07, 66.71),
    vector4(65.02, 6345.89, 31.22, 206.64),
    vector4(-303.28, 6118.17, 31.50, 135.24),
    vector4(-63.41, -2015.25, 18.02, 299.48),
    vector4(235.04, -1520.18, 29.15, 316.76),
    vector4(350.40, -2466.90, 6.40, 169.38),
    vector4(1213.97, -1229.01, 35.35, 270.74),
    vector4(729.09, -2023.63, 29.31, 268.75),
    vector4(551.76, -1840.26, 25.34, 40.72),
    vector4(2665.40, 1700.63, 24.49, 269.33),
    vector4(1635.54, 3562.84, 35.23, 296.61),
    vector4(2744.55, 3412.43, 56.57, 247.48),
    vector4(1972.17, 3839.16, 32.00, 304.36),
    vector4(1716.00, 4706.41, 42.69, 91.44),
    vector4(2471.47, 4463.07, 35.30, 277.56),
    vector4(2730.39, 2778.20, 36.01, 134.51),
    vector4(2534.83, 2589.08, 37.95, 2.48),
    vector4(860.47, -896.87, 25.53, 181.80),
    vector4(1246.34, 1860.78, 79.47, 315.78),
    vector4(-1827.50, 2934.11, 32.82, 59.53),
    vector4(-2444.59, 2981.63, 32.82, 283.55),
    vector4(-1087.80, -2047.55, 13.23, 314.93),
    vector4(850.42, 2197.69, 51.93, 243.19),
    vector4(822.72, -2134.28, 29.29, 349.36),
    vector4(942.22, -2487.76, 28.34, 89.41),
    vector4(783.08, -2523.98, 20.51, 5.67),
    vector4(983.00, -1230.77, 25.38, 121.40),
    vector4(1528.10, 1719.32, 109.97, 34.60),
    vector4(2846.31, 1463.10, 24.56, 74.93),
    vector4(3631.05, 3768.61, 28.52, 320.00),
    vector4(2919.03, 4337.85, 50.31, 203.77),
    vector4(2802.35, 4838.31, 44.99, 118.49),
    vector4(-704.20, 5772.55, 17.34, 68.44),
    vector4(2204.73, 5574.04, 53.74, 351.31)
}
