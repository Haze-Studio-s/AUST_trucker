-- =======================================
-- AURP_TRUCKER - SISTEMA DE INDÚSTRIAS
-- =======================================

Config = Config or {}

-- Configuração de Idioma e Formatação (Sincronização NUI e Servidor)
Config.lang = 'br'
Config.locale = 'br'
Config.format = {
    lang = 'br',
    currency = 'USD',
    location = 'pt-BR'
}

-- Framework suportado: 'qbx' | 'qbcore' | 'esx'
Config.Framework = 'qbx'

-- Debug
Config.Debug = false

-- =======================================
-- CAPACIDADE DE CARGA POR CLASSE DE VEÍCULO
-- Classe GTA V (GetVehicleClass native)
-- maxWeight em kg — jobs com peso > maxWeight reduzem cargoQty
-- =======================================
Config.VehicleCapacity = {
    [0]  = { maxWeight = 50,  label = "Compacto" },
    [1]  = { maxWeight = 80,  label = "Sedan" },
    [2]  = { maxWeight = 120, label = "SUV" },
    [3]  = { maxWeight = 60,  label = "Cupê" },
    [4]  = { maxWeight = 100, label = "Muscle" },
    [5]  = { maxWeight = 40,  label = "Esportivo" },
    [6]  = { maxWeight = 30,  label = "Super" },
    [7]  = { maxWeight = 20,  label = "Moto" },
    [8]  = { maxWeight = 80,  label = "Off-Road" },
    [9]  = { maxWeight = 200, label = "Industrial" },
    [10] = { maxWeight = 250, label = "Utilitário" },
    [11] = { maxWeight = 200, label = "Van" },
    [12] = { maxWeight = 0,   label = "Bicicleta" },
    [13] = { maxWeight = 0,   label = "Barco" },
    [14] = { maxWeight = 0,   label = "Helicóptero" },
    [15] = { maxWeight = 0,   label = "Avião" },
    [16] = { maxWeight = 250, label = "Serviço" },
    [17] = { maxWeight = 0,   label = "Emergência" },
    [18] = { maxWeight = 250, label = "Militar" },
    [19] = { maxWeight = 300, label = "Comercial" },
    [20] = { maxWeight = 400, label = "Caminhão" },
}

-- =======================================
-- SISTEMA DE CONTRATOS (Entregas de Empresa)
-- =======================================
Config.Contracts = {
    refreshInterval = 300000,  -- 5 min entre geração de novos contratos
    maxAvailable    = 5,       -- max contratos disponíveis na lista
    maxActive       = 1,       -- max contratos ativos por jogador
    requireCompany  = true,
    requireTrailer  = true,
    types = {
        simple = { paymentMult = 2.0, stops = 1 },
        multi  = { paymentMult = 1.5, minStops = 3, maxStops = 5 },  -- mult por parada
    },
}

Config.ClientSectors = {
    food         = { label = "Alimentos",    premiumAt = 3 },
    construction = { label = "Construção",   premiumAt = 3 },
    petrol       = { label = "Combustíveis", premiumAt = 4 },
    chemical     = { label = "Químicos",     premiumAt = 4 },
    mixed        = { label = "Geral",        premiumAt = 3 },
}

Config.TrustLevels = {
    [1] = { xpRequired = 0,    bonusPercent = 0,  label = "Novo",       maxOptions = 1 },
    [2] = { xpRequired = 500,  bonusPercent = 10, label = "Conhecido",  maxOptions = 2 },
    [3] = { xpRequired = 1500, bonusPercent = 20, label = "Confiável",  maxOptions = 3 },
    [4] = { xpRequired = 3500, bonusPercent = 35, label = "Parceiro",   maxOptions = 4 },
    [5] = { xpRequired = 7000, bonusPercent = 50, label = "Exclusivo",  maxOptions = 5 },
}

Config.ContractNegotiation = {
    volumes     = { 1, 3, 5, 8, 12 },
    prazos      = { 30, 45, 60, 90, 120 },
    frequencias = { 1, 2, 3, 5, 7 },
}

-- =======================================
-- EMPRESA DE TRAILERS
-- =======================================
Config.TrailerCompany = {
    name = "Truck Logistics — Sede Principal",
    coords = vector3(1208.83, -3115.0, 5.54),
    spawnCoords = vector4(1274.21, -3186.43, 5.91, 90.0),

    -- Trailers disponíveis
    trailers = {
        {model = "tanker", label = "Caminhão Tanque", price = 0},
        {model = "freighttrailer", label = "Chassi Porta-Contêiner (40ft / 20ft)", price = 0},
        {model = "trailers", label = "Baú Carga Geral", price = 0},
        {model = "trailers2", label = "Baú Duplo / Frigorífico", price = 0}
    }
}

-- =======================================
-- SISTEMA DE ALUGUEL DE CAMINHÕES COM CAUÇÃO
-- =======================================
Config.TruckRental = {
    enabled       = true,
    pedModel      = 's_m_y_dockwork_01',
    pedCoords     = vector4(1208.83, -3115.0, 5.54, 90.0),
    spawnCoords   = vector4(1250.55, -3162.4, 5.88, 270.0),
    returnCoords  = vector3(1250.55, -3162.4, 5.88),
    returnRadius  = 25.0,
    depositAmount = 1500, -- Caução devolvida após devolução sem avarias
    rentalFee     = 300,  -- Custo de locação
    trucks = {
        { model = 'hauler',  label = 'Hauler Comercial', deposit = 1500, fee = 300 },
        { model = 'phantom', label = 'Phantom Clássico',  deposit = 1500, fee = 300 },
        { model = 'packer',  label = 'Packer Pesado',     deposit = 2000, fee = 400 },
    }
}

-- =======================================
-- SISTEMA DE INDÚSTRIAS PRIMÁRIAS E SECUNDÁRIAS
-- =======================================

-- Indústrias Primárias (Origens - onde se carrega)
Config.PrimaryIndustries = {
    {
        id = "terminal_a1",
        name = "Terminal Portuário A1",
        coords = vector3(361.62, -2541.45, 5.74),
        type = "mixed",
        products = {
            {name = "Containers", weight = 150, trailer = "trailers2", basePrice = 850, loadTime = 10000, icon = "fas fa-box"},
            {name = "Carga Geral", weight = 80, trailer = "trailers", basePrice = 700, loadTime = 8000, icon = "fas fa-boxes"},
            {name = "Combustível Marítimo", weight = 200, trailer = "tanker", basePrice = 950, loadTime = 11000, icon = "fas fa-ship", adr = 'flammable_liquid'}
        }
    },
    {
        id = "terminal_a2",
        name = "Terminal Portuário A2",
        coords = vector3(1185.48, -3028.04, 5.9),
        type = "mixed",
        products = {
            {name = "Mercadorias Importadas", weight = 150, trailer = "trailers2", basePrice = 900, loadTime = 11000, icon = "fas fa-shipping-fast"},
            {name = "Equipamentos", weight = 80, trailer = "trailers", basePrice = 750, loadTime = 9000, icon = "fas fa-tools"}
        }
    },
    {
        id = "lamesa_industrial",
        name = "Armazém La Mesa",
        coords = vector3(808.34, -841.19, 26.36),
        type = "construction",
        products = {
            {name = "Materiais de Construção", weight = 150, trailer = "trailers2", basePrice = 780, loadTime = 9500, icon = "fas fa-hammer"},
            {name = "Ferramentas", weight = 80, trailer = "trailers", basePrice = 650, loadTime = 7500, icon = "fas fa-toolbox"}
        }
    },
    {
        id = "lamesa_warehouse",
        name = "Depósito La Mesa",
        coords = vector3(699.85, -1112.91, 22.52),
        type = "food",
        products = {
            {name = "Alimentos Secos", weight = 80, trailer = "trailers", basePrice = 600, loadTime = 7000, icon = "fas fa-shopping-cart"},
            {name = "Bebidas", weight = 80, trailer = "trailers", basePrice = 550, loadTime = 6500, icon = "fas fa-wine-bottle"}
        }
    },
    {
        id = "terminal_b1",
        name = "Terminal B1 - Porto LS",
        coords = vector3(627.38, -2890.94, 6.04),
        type = "petrol",
        products = {
            {name = "Combustível", weight = 200, trailer = "tanker", basePrice = 820, loadTime = 10000, icon = "fas fa-gas-pump", adr = 'flammable_liquid'},
            {name = "Diesel", weight = 200, trailer = "tanker", basePrice = 750, loadTime = 9000, icon = "fas fa-oil-can", adr = 'flammable_liquid'}
        }
    },
    {
        id = "cypress_depot",
        name = "Depósito Cypress Flats",
        coords = vector3(728.93, -1370.37, 26.39),
        type = "mixed",
        products = {
            {name = "Carga Industrial", weight = 80, trailer = "trailers", basePrice = 680, loadTime = 8000, icon = "fas fa-industry"},
            {name = "Peças Mecânicas", weight = 80, trailer = "trailers", basePrice = 720, loadTime = 8500, icon = "fas fa-cog"}
        }
    },
    {
        id = "cypress_warehouse",
        name = "Armazém Cypress Flats",
        coords = vector3(903.88, -1735.43, 30.51),
        type = "construction",
        products = {
            {name = "Cimento", weight = 150, trailer = "trailers2", basePrice = 700, loadTime = 8500, icon = "fas fa-fill-drip"},
            {name = "Areia", weight = 150, trailer = "trailers2", basePrice = 620, loadTime = 7500, icon = "fas fa-mountain"}
        }
    },
    {
        id = "terminal_c1",
        name = "Terminal C1 - Porto LS",
        coords = vector3(1126.46, -2914.82, 5.9),
        type = "mixed",
        products = {
            {name = "Eletrônicos", weight = 80, trailer = "trailers", basePrice = 950, loadTime = 11000, icon = "fas fa-laptop"},
            {name = "Tecnologia", weight = 80, trailer = "trailers", basePrice = 880, loadTime = 10000, icon = "fas fa-microchip"}
        }
    },
    {
        id = "terminal_d1",
        name = "Terminal D1 - Porto LS",
        coords = vector3(1273.67, -3187.22, 5.9),
        type = "petrol",
        products = {
            {name = "Petróleo Refinado", weight = 200, trailer = "tanker", basePrice = 870, loadTime = 10500, icon = "fas fa-oil-can", adr = 'flammable_liquid'},
            {name = "Gasolina Premium", weight = 200, trailer = "tanker", basePrice = 800, loadTime = 9500, icon = "fas fa-gas-pump", adr = 'flammable_liquid'}
        }
    },
    {
        id = "terminal_d2",
        name = "Terminal D2 - Porto LS",
        coords = vector3(799.08, -2934.35, 5.89),
        type = "chemical",
        products = {
            {name = "Produtos Químicos", weight = 80, trailer = "trailers", basePrice = 750, loadTime = 9000, icon = "fas fa-flask", adr = 'toxic'},
            {name = "Fertilizantes", weight = 80, trailer = "trailers", basePrice = 680, loadTime = 8000, icon = "fas fa-seedling", adr = 'environmental'},
            {name = "Químicos Líquidos", weight = 200, trailer = "tanker", basePrice = 820, loadTime = 9500, icon = "fas fa-vial", adr = 'toxic'}
        }
    },
    {
        id = "terminal_e1",
        name = "Terminal E1 - Porto LS",
        coords = vector3(842.91, -3033.88, 5.74),
        type = "mixed",
        products = {
            {name = "Têxteis", weight = 80, trailer = "trailers", basePrice = 640, loadTime = 7500, icon = "fas fa-tshirt"},
            {name = "Vestuário", weight = 80, trailer = "trailers", basePrice = 600, loadTime = 7000, icon = "fas fa-shopping-bag"}
        }
    },
    {
        id = "terminal_e2",
        name = "Terminal E2 - Porto LS",
        coords = vector3(1273.62, -3202.21, 5.9),
        type = "construction",
        products = {
            {name = "Aço", weight = 150, trailer = "trailers2", basePrice = 820, loadTime = 9500, icon = "fas fa-industry"},
            {name = "Ferro", weight = 150, trailer = "trailers2", basePrice = 760, loadTime = 8800, icon = "fas fa-weight-hanging"}
        }
    },
    {
        id = "industrial_park",
        name = "Parque Industrial Davis",
        coords = vector3(838.7, -1984.29, 29.3),
        type = "mixed",
        products = {
            {name = "Móveis", weight = 80, trailer = "trailers", basePrice = 720, loadTime = 8500, icon = "fas fa-couch"},
            {name = "Eletrodomésticos", weight = 80, trailer = "trailers", basePrice = 780, loadTime = 9000, icon = "fas fa-tv"}
        }
    },
    {
        id = "terminal_f1",
        name = "Terminal F1 - Porto LS",
        coords = vector3(1212.03, -2958.28, 5.87),
        type = "food",
        products = {
            {name = "Alimentos Refrigerados", weight = 80, trailer = "trailers", basePrice = 690, loadTime = 8000, icon = "fas fa-ice-cream"},
            {name = "Congelados", weight = 80, trailer = "trailers", basePrice = 720, loadTime = 8500, icon = "fas fa-snowflake"}
        }
    },
    {
        id = "terminal_f2",
        name = "Terminal F2 - Porto LS",
        coords = vector3(1180.0, -2913.84, 5.9),
        type = "mixed",
        products = {
            {name = "Papel", weight = 80, trailer = "trailers", basePrice = 580, loadTime = 6800, icon = "fas fa-file-alt"},
            {name = "Papelão", weight = 80, trailer = "trailers", basePrice = 540, loadTime = 6500, icon = "fas fa-box-open"}
        }
    },
    {
        id = "davis_industrial",
        name = "Zona Industrial Davis",
        coords = vector3(448.96, -1968.45, 22.94),
        type = "construction",
        products = {
            {name = "Madeira", weight = 150, trailer = "trailers2", basePrice = 650, loadTime = 7800, icon = "fas fa-tree"},
            {name = "Compensados", weight = 80, trailer = "trailers", basePrice = 600, loadTime = 7200, icon = "fas fa-layer-group"}
        }
    },
    {
        id = "terminal_g1",
        name = "Terminal G1 - Porto LS",
        coords = vector3(1270.54, -3294.52, 5.9),
        type = "mixed",
        products = {
            {name = "Vidros", weight = 80, trailer = "trailers", basePrice = 710, loadTime = 8200, icon = "fas fa-window-restore"},
            {name = "Cerâmica", weight = 80, trailer = "trailers", basePrice = 670, loadTime = 7800, icon = "fas fa-circle"}
        }
    },
    {
        id = "terminal_h1",
        name = "Terminal H1 - Porto LS",
        coords = vector3(1137.69, -3099.89, 5.86),
        type = "petrol",
        products = {
            {name = "Óleo Diesel", weight = 200, trailer = "tanker", basePrice = 740, loadTime = 8800, icon = "fas fa-oil-can", adr = 'flammable_liquid'},
            {name = "Lubrificantes", weight = 200, trailer = "tanker", basePrice = 690, loadTime = 8200, icon = "fas fa-tint", adr = 'flammable_liquid'},
            {name = "Óleo de Motor", weight = 200, trailer = "tanker", basePrice = 720, loadTime = 8500, icon = "fas fa-oil-can", adr = 'flammable_liquid'}
        }
    },
    {
        id = "strawberry_depot",
        name = "Depósito Strawberry",
        coords = vector3(238.61, -2240.85, 5.86),
        type = "food",
        products = {
            {name = "Frutas e Vegetais", weight = 80, trailer = "trailers", basePrice = 620, loadTime = 7400, icon = "fas fa-apple-alt"},
            {name = "Produtos Frescos", weight = 80, trailer = "trailers", basePrice = 660, loadTime = 7800, icon = "fas fa-carrot"}
        }
    },
    {
        id = "terminal_i1",
        name = "Terminal Aeroporto LS",
        coords = vector3(1274.17, -3230.06, 5.9),
        type = "mixed",
        products = {
            {name = "Carga Aérea", weight = 80, trailer = "trailers", basePrice = 920, loadTime = 11000, icon = "fas fa-plane"},
            {name = "Correio Expresso", weight = 80, trailer = "trailers", basePrice = 850, loadTime = 10000, icon = "fas fa-shipping-fast"}
        }
    },
    {
        id = "lsia_warehouse_cargo",
        name = "Armazém LSIA",
        coords = vector3(-181.65, -2246.78, 7.81),
        type = "mixed",
        products = {
            {name = "Bagagens", weight = 80, trailer = "trailers", basePrice = 560, loadTime = 6700, icon = "fas fa-suitcase"},
            {name = "Encomendas", weight = 80, trailer = "trailers", basePrice = 590, loadTime = 7000, icon = "fas fa-box"}
        }
    },
    {
        id = "davis_warehouse",
        name = "Armazém Davis",
        coords = vector3(-54.54, -1836.6, 26.56),
        type = "mixed",
        products = {
            {name = "Produtos Diversos", weight = 80, trailer = "trailers", basePrice = 640, loadTime = 7600, icon = "fas fa-boxes"},
            {name = "Mercadorias Gerais", weight = 80, trailer = "trailers", basePrice = 680, loadTime = 8000, icon = "fas fa-store"}
        }
    },
    -- =======================================
    -- ORIGENS DE PEQUENAS ENTREGAS (van/furgão)
    -- =======================================
    {
        id = "downtown_post",
        name = "Correios Downtown",
        coords = vector3(103.94, -1084.05, 29.38),
        type = "mixed",
        products = {
            {name = "Encomendas Expressas",   weight = 20, trailer = "van", basePrice = 220, loadTime = 3000, icon = "fas fa-box"},
            {name = "Documentos",             weight = 20, trailer = "van", basePrice = 180, loadTime = 2500, icon = "fas fa-file-alt"},
        }
    },
    {
        id = "mirror_park_depot",
        name = "Depósito Mirror Park",
        coords = vector3(1201.48, -479.37, 66.62),
        type = "mixed",
        products = {
            {name = "Refeições Prontas",  weight = 20, trailer = "van", basePrice = 200, loadTime = 2500, icon = "fas fa-utensils"},
            {name = "Bebidas e Snacks",   weight = 20, trailer = "van", basePrice = 190, loadTime = 2500, icon = "fas fa-coffee"},
        }
    },
    {
        id = "vespucci_market_origin",
        name = "Mercado Vespucci",
        coords = vector3(-1222.38, -896.77, 12.0),
        type = "food",
        products = {
            {name = "Hortifrutti",       weight = 20, trailer = "van", basePrice = 210, loadTime = 3000, icon = "fas fa-apple-alt"},
            {name = "Flores e Plantas",  weight = 20, trailer = "van", basePrice = 195, loadTime = 2500, icon = "fas fa-seedling"},
        }
    }
}

-- Indústrias Secundárias (Destinos - onde se entrega)
Config.SecondaryIndustries = {
    {
        id = "lamesa_store",
        name = "Loja La Mesa",
        coords = vector3(1004.78, -1381.54, 31.37),
        type = "mixed",
        acceptedProducts = {"Eletrônicos", "Tecnologia", "Móveis", "Eletrodomésticos", "Produtos Diversos", "Mercadorias Gerais"},
        multiplier = 1.1,
        unloadTime = 7000
    },
    {
        id = "vinewood_shop",
        name = "Loja Vinewood Hills",
        coords = vector3(137.82, 312.4, 112.14),
        type = "mixed",
        acceptedProducts = {"Têxteis", "Vestuário", "Eletrônicos", "Móveis", "Produtos Diversos"},
        multiplier = 1.3,
        unloadTime = 8000
    },
    {
        id = "vinewood_store",
        name = "Estabelecimento Vinewood",
        coords = vector3(581.68, 130.11, 98.04),
        type = "mixed",
        acceptedProducts = {"Alimentos Secos", "Bebidas", "Produtos Frescos", "Frutas e Vegetais"},
        multiplier = 1.2,
        unloadTime = 6500
    },
    {
        id = "vespucci_business",
        name = "Comércio Vespucci",
        coords = vector3(-1057.19, -2019.36, 13.16),
        type = "food",
        acceptedProducts = {"Alimentos Refrigerados", "Congelados", "Alimentos Secos", "Bebidas"},
        multiplier = 1.0,
        unloadTime = 6000
    },
    {
        id = "vinewood_retail",
        name = "Loja Vinewood East",
        coords = vector3(690.81, 603.72, 128.91),
        type = "mixed",
        acceptedProducts = {"Vidros", "Cerâmica", "Materiais de Construção", "Ferramentas"},
        multiplier = 1.2,
        unloadTime = 7500
    },
    {
        id = "senora_depot",
        name = "Depósito Grand Senora",
        coords = vector3(1525.84, 785.08, 77.43),
        type = "construction",
        acceptedProducts = {"Materiais de Construção", "Cimento", "Areia", "Aço", "Ferro", "Madeira", "Compensados"},
        multiplier = 1.4,
        unloadTime = 9000
    },
    {
        id = "chumash_store",
        name = "Loja Chumash",
        coords = vector3(-2965.65, 370.62, 14.74),
        type = "mixed",
        acceptedProducts = {"Alimentos Secos", "Bebidas", "Produtos Frescos", "Encomendas", "Bagagens"},
        multiplier = 1.1,
        unloadTime = 6500
    },
    {
        id = "sandy_warehouse",
        name = "Armazém Sandy Shores",
        coords = vector3(1206.53, 1859.04, 78.92),
        type = "mixed",
        acceptedProducts = {"Containers", "Carga Geral", "Mercadorias Importadas", "Equipamentos", "Carga Industrial"},
        multiplier = 1.3,
        unloadTime = 8500
    },
    {
        id = "harmony_shop",
        name = "Loja Harmony",
        coords = vector3(736.88, 2534.39, 73.17),
        type = "petrol",
        acceptedProducts = {"Combustível", "Diesel", "Petróleo Refinado", "Gasolina Premium", "Óleo Diesel", "Lubrificantes", "Combustível Marítimo", "Químicos Líquidos", "Óleo de Motor"},
        multiplier = 1.2,
        unloadTime = 8000
    },
    {
        id = "harmony_depot",
        name = "Depósito Harmony",
        coords = vector3(585.82, 2790.33, 42.17),
        type = "construction",
        acceptedProducts = {"Materiais de Construção", "Ferramentas", "Cimento", "Aço", "Madeira"},
        multiplier = 1.1,
        unloadTime = 7500
    },
    {
        id = "zancudo_facility",
        name = "Instalação Zancudo River",
        coords = vector3(-1142.25, 2680.74, 18.1),
        type = "mixed",
        acceptedProducts = {"Equipamentos", "Tecnologia", "Eletrônicos", "Peças Mecânicas"},
        multiplier = 1.5,
        unloadTime = 10000
    },
    {
        id = "morningwood_store",
        name = "Loja Morningwood",
        coords = vector3(-1782.78, -379.43, 44.98),
        type = "mixed",
        acceptedProducts = {"Alimentos Secos", "Bebidas", "Produtos Frescos", "Frutas e Vegetais"},
        multiplier = 1.0,
        unloadTime = 6000
    },
    {
        id = "airport_depot",
        name = "Depósito LSIA",
        coords = vector3(-675.84, -2390.05, 13.85),
        type = "mixed",
        acceptedProducts = {"Carga Aérea", "Correio Expresso", "Bagagens", "Encomendas"},
        multiplier = 1.4,
        unloadTime = 9000
    },
    {
        id = "ocean_store",
        name = "Loja Great Ocean Highway",
        coords = vector3(-3156.71, 1150.7, 21.07),
        type = "food",
        acceptedProducts = {"Alimentos Secos", "Bebidas", "Alimentos Refrigerados", "Congelados"},
        multiplier = 1.2,
        unloadTime = 7000
    },
    {
        id = "lsia_warehouse_south",
        name = "Armazém LSIA Sul",
        coords = vector3(-878.02, -2732.84, 13.83),
        type = "petrol",
        acceptedProducts = {"Combustível", "Diesel", "Petróleo Refinado", "Gasolina Premium", "Combustível Marítimo", "Óleo de Motor", "Lubrificantes"},
        multiplier = 1.3,
        unloadTime = 8500
    },
    {
        id = "airport_facility",
        name = "Instalação LSIA",
        coords = vector3(-1026.11, -2374.17, 13.94),
        type = "mixed",
        acceptedProducts = {"Containers", "Carga Geral", "Carga Aérea", "Equipamentos"},
        multiplier = 1.2,
        unloadTime = 8000
    },
    {
        id = "elysian_depot",
        name = "Depósito Elysian Island",
        coords = vector3(143.59, -3000.76, 7.03),
        type = "mixed",
        acceptedProducts = {"Containers", "Mercadorias Importadas", "Carga Geral", "Papel", "Papelão"},
        multiplier = 1.1,
        unloadTime = 7500
    },
    {
        id = "airport_terminal",
        name = "Terminal LSIA",
        coords = vector3(-317.46, -2745.42, 6.01),
        type = "chemical",
        acceptedProducts = {"Produtos Químicos", "Fertilizantes"},
        multiplier = 1.3,
        unloadTime = 8500
    },
    {
        id = "delperro_shop",
        name = "Loja Del Perro",
        coords = vector3(-1267.14, -820.18, 17.1),
        type = "mixed",
        acceptedProducts = {"Têxteis", "Vestuário", "Eletrônicos", "Móveis", "Eletrodomésticos"},
        multiplier = 1.1,
        unloadTime = 7000
    },
    {
        id = "littleseoul_store",
        name = "Loja Little Seoul",
        coords = vector3(-744.11, -1504.82, 4.98),
        type = "food",
        acceptedProducts = {"Alimentos Secos", "Bebidas", "Alimentos Refrigerados", "Frutas e Vegetais", "Produtos Frescos"},
        multiplier = 1.0,
        unloadTime = 6500
    },
    {
        id = "rockford_business",
        name = "Comércio Rockford Hills",
        coords = vector3(-1151.9, -205.66, 37.96),
        type = "mixed",
        acceptedProducts = {"Eletrônicos", "Tecnologia", "Móveis", "Eletrodomésticos", "Vestuário", "Têxteis"},
        multiplier = 1.4,
        unloadTime = 9000
    },
    {
        id = "littleseoul_market",
        name = "Mercado Little Seoul",
        coords = vector3(-827.32, -1263.61, 5.0),
        type = "food",
        acceptedProducts = {"Alimentos Secos", "Bebidas", "Frutas e Vegetais", "Produtos Frescos", "Alimentos Refrigerados"},
        multiplier = 1.0,
        unloadTime = 6000
    },
    -- Destinos de pequenas entregas (van/furgão)
    {
        id = "pillbox_hospital",
        name = "Hospital Pillbox Hill",
        coords = vector3(355.17, -584.49, 28.72),
        type = "mixed",
        acceptedProducts = {"Encomendas Expressas", "Documentos", "Refeições Prontas"},
        multiplier = 1.1,
        unloadTime = 3000
    },
    {
        id = "cityhall_offices",
        name = "Prefeitura / Centro Cívico",
        coords = vector3(-274.67, -885.56, 31.07),
        type = "mixed",
        acceptedProducts = {"Documentos", "Encomendas Expressas"},
        multiplier = 1.0,
        unloadTime = 2500
    },
    {
        id = "maze_bank_tower",
        name = "Maze Bank Tower",
        coords = vector3(-75.03, -826.36, 243.39),
        type = "mixed",
        acceptedProducts = {"Documentos", "Encomendas Expressas", "Refeições Prontas"},
        multiplier = 1.3,
        unloadTime = 3000
    },
    {
        id = "strawberry_market",
        name = "Mercado Strawberry",
        coords = vector3(-1205.59, -1569.39, 4.61),
        type = "food",
        acceptedProducts = {"Hortifrutti", "Flores e Plantas", "Bebidas e Snacks"},
        multiplier = 1.0,
        unloadTime = 3000
    },
    {
        id = "grove_corner_store",
        name = "Mercearia Grove Street",
        coords = vector3(-9.25, -1442.21, 30.52),
        type = "food",
        acceptedProducts = {"Hortifrutti", "Bebidas e Snacks", "Refeições Prontas"},
        multiplier = 0.9,
        unloadTime = 2500
    },
    {
        id = "vinewood_florist",
        name = "Floricultura Vinewood",
        coords = vector3(335.6, 322.02, 103.57),
        type = "mixed",
        acceptedProducts = {"Flores e Plantas"},
        multiplier = 1.2,
        unloadTime = 2500
    },
    {
        id = "eclipse_towers",
        name = "Eclipse Towers",
        coords = vector3(-770.55, 312.39, 85.69),
        type = "mixed",
        acceptedProducts = {"Encomendas Expressas", "Refeições Prontas", "Bebidas e Snacks"},
        multiplier = 1.2,
        unloadTime = 3000
    },
    -- Postos de Gasolina (vp_gasstations)
    {
        id = "station_strawberry",
        name = "Posto Globe Oil - Strawberry",
        coords = vector3(-71.28, -1761.16, 29.48),
        type = "petrol",
        acceptedProducts = {"Combustível", "Diesel", "Petróleo Refinado", "Gasolina Premium", "Óleo Diesel", "Lubrificantes"},
        multiplier = 1.25,
        unloadTime = 8500
    },
    {
        id = "station_innocence",
        name = "Posto RON - Innocence Blvd",
        coords = vector3(264.74, -1260.98, 29.18),
        type = "petrol",
        acceptedProducts = {"Combustível", "Diesel", "Petróleo Refinado", "Gasolina Premium", "Óleo Diesel", "Lubrificantes"},
        multiplier = 1.25,
        unloadTime = 8500
    },
    {
        id = "station_davis",
        name = "Posto RON - Davis",
        coords = vector3(175.31, -1561.73, 29.26),
        type = "petrol",
        acceptedProducts = {"Combustível", "Diesel", "Petróleo Refinado", "Gasolina Premium", "Óleo Diesel", "Lubrificantes"},
        multiplier = 1.25,
        unloadTime = 8500
    },
    {
        id = "station_paleto",
        name = "Posto RON - Paleto Blvd",
        coords = vector3(1702.79, 6416.86, 33.64),
        type = "petrol",
        acceptedProducts = {"Combustível", "Diesel", "Petróleo Refinado", "Gasolina Premium", "Óleo Diesel", "Lubrificantes"},
        multiplier = 1.45,
        unloadTime = 9500
    }
}

-- Configurações de geração de trabalhos
Config.JobGeneration = {
    maxActiveJobs = 8, -- Máximo de trabalhos disponíveis
    refreshInterval = 1800000, -- 30 minutos em ms

    -- Sistema de expiração dinâmica baseado no pagamento
    -- GP-C01: basePayment atualizado de 1000 → 4000 para refletir a nova escala de pagamento.
    -- Jobs de alta carga/distância (~$5000-$8000) expiram em 15 min (exclusivos e disputados).
    -- Jobs simples de van (~$200-$400) expiram em 45 min (mais fáceis de encontrar).
    jobExpiration = {
        minTime     = 900,   -- 15 minutos (jobs de alto valor)
        maxTime     = 2700,  -- 45 minutos (jobs de baixo valor)
        basePayment = 4000,  -- Pagamento de referência (ponto médio da nova escala)
    },

    -- GP-H01: elevado de 0.05 → 4.0 para que distância contribua de forma
    -- significativa (~$15-25/km). Rota de 200km agora vale ~$800 de bônus base.
    distanceMultiplier = 4.0, -- $ por km de distância

    -- GP-H03: slow.multiplier de 0.8 → 1.0 (sem penalidade para rotas longas)
    -- slow.time de 900s (15min) → 2400s (40min) — apenas viagens muito longas
    -- deixam de ter bônus, sem nunca punir.
    timeBonus = {
        fast   = { time = 600,  multiplier = 1.2 }, -- < 10 min → +20%
        normal = { time = 1200, multiplier = 1.0 }, -- < 20 min → neutro
        slow   = { time = 2400, multiplier = 1.0 }, -- qualquer coisa acima → neutro (sem penalidade)
    },
    DemandWeighting = true,  -- pesa geração de jobs por demanda real (Fase 2)
}


-- =======================================
-- SISTEMA DE ECONOMIA DINÂMICA
-- =======================================
Config.Economy = {
    -- Intervalo de atualização de preços (em ms)
    priceUpdateInterval = 1200000, -- 20 minutos

    -- Intervalo de produção para indústrias PRIMÁRIAS (em ms)
    primaryProductionInterval = 60000, -- 1 minuto (produz 1 item a cada 1 min)

    -- Intervalo de produção para indústrias SECUNDÁRIAS (em ms)
    secondaryProductionInterval = 600000, -- 10 minutos (produz 1 item a cada 10 min)

    -- Limites de preço (multiplicadores do preço base)
    priceFloor = 0.5,  -- Preço mínimo: 50% do base
    priceCeiling = 2.0, -- Preço máximo: 200% do base

    -- Velocidade de ajuste de preços
    priceAdjustmentSpeed = 0.15, -- 15% de ajuste por ciclo

    -- NPC fail-safe (Fase 2):
    npcFailsafeDelay  = 1800,   -- segundos sem insumos antes de NPC abastecer (30min)
    npcFailsafeAmount = 10,     -- unidades que o NPC entrega por ativação

    -- Debug logs detalhados
    detailedLogs = true
}

-- =======================================
-- SISTEMA DE INDÚSTRIAS - EMPRESAS
-- =======================================
Config.Industries = {
    -- Fleeca Food Processing (Indústria Secundária - Processa e Vende)
    fleeca_foods = {
        id = "fleeca_foods",
        name = "Fleeca Food Processing",
        welcomeMessage = "Bem-vindo à Fleeca Food Processing!",
        coords = vector3(-582.3, -1126.4, 22.2),
        type = "secondary", -- secondary = processa matéria-prima
        production = {
            item = "food",
            label = "Comida Processada",
            productionPerHour = 15,
            maxStock = 400,
            unit = "caixas",
            basePrice = 190
        },
        consumption = {
            {item = "meat", label = "Carne", consumptionPerHour = 10, maxStock = 200, unit = "caixas", basePrice = 120},
            {item = "water", label = "Água", consumptionPerHour = 100, maxStock = 1000, unit = "galões", basePrice = 10}
        }
    },

    -- Ron Alternates Wind Farm Refinery (Indústria Primária - Só Vende)
    ron_refinery = {
        id = "ron_refinery",
        name = "Ron Alternates Wind Farm",
        welcomeMessage = "Bem-vindo à Ron Alternates Wind Farm!",
        coords = vector3(2540.0, 2594.0, 37.9),
        type = "primary", -- primary = só vende (não compra)
        production = {
            item = "fuel",
            label = "Combustível",
            productionPerHour = 25,
            maxStock = 1000,
            unit = "barris",
            basePrice = 320
        },
        consumption = {}
    },

    -- Jetsam Cement Works (Indústria Primária - Só Vende)
    jetsam_cement = {
        id = "jetsam_cement",
        name = "Jetsam Cement Works",
        welcomeMessage = "Bem-vindo à Jetsam Cement Works!",
        coords = vector3(1374.6, -2076.3, 52.0),
        type = "primary", -- primary = só vende (não compra)
        production = {
            item = "cement",
            label = "Cimento",
            productionPerHour = 40,
            maxStock = 1500,
            unit = "sacos",
            basePrice = 110
        },
        consumption = {}
    },

    -- Humane Labs and Research (Indústria Secundária - Processa e Vende)
    humane_labs = {
        id = "humane_labs",
        name = "Humane Labs",
        welcomeMessage = "Bem-vindo à Humane Labs and Research!",
        coords = vector3(2725.5, 1533.2, 24.5),
        type = "secondary", -- secondary = processa matéria-prima
        production = {
            item = "chemicals",
            label = "Produtos Químicos",
            productionPerHour = 20,
            maxStock = 600,
            unit = "caixas",
            basePrice = 250
        },
        consumption = {
            {item = "water", label = "Água", consumptionPerHour = 30, maxStock = 500, unit = "litros", basePrice = 10}
        }
    },

    -- 24/7 Distribution Center (Indústria Terciária - Só Compra)
    twentyfourseven_dist = {
        id = "twentyfourseven_dist",
        name = "24/7 Distribution Center",
        welcomeMessage = "Bem-vindo ao 24/7 Distribution Center!",
        coords = vector3(547.8, 2671.2, 42.2),
        type = "tertiary", -- tertiary = só compra (não produz)
        production = nil, -- Não produz nada
        consumption = {
            {item = "food", label = "Comida", consumptionPerHour = 20, maxStock = 400, unit = "caixas", basePrice = 190}
        }
    }
}

-- =======================================
-- CONFIGURAÇÕES GERAIS
-- =======================================
Config.General = {
    -- Distâncias de interação
    interactionDistance = 5.0,

    -- Contratos (CompleteStop): observabilidade + endurecimento opcional
    -- Ver AUDIT_REPORT.md — logs em falhas suspeitas; raios separados pickup/delivery reduzem falsos positivos.
    contractAnticheat = {
        securityLog = true,
        requireVehicle = false,
        distanceMultiplier = 3.0,
        pickupDistanceMultiplier = 3.5,
        deliveryDistanceMultiplier = 3.0,
    },

    -- GP-M02: deliveryTimeBonus removido daqui (duplicata não usada).
    -- O sistema usa Config.JobGeneration.timeBonus.

    -- Configurações de pagamento
    -- GP-C01: teto elevado de 2000 → 8000 para permitir que a fórmula
    -- (basePrice × cargoQty + dist × distMult) produza pagamentos proporcionais
    -- ao esforço real da entrega.
    payment = {
        currency = "cash",
        maxPayment = 8000
    }
}

Config.Loans = {
    MinAmount        = 10000,      -- valor mínimo de empréstimo
    MaxAmount        = 500000,     -- valor máximo
    InterestRate     = 0.05,       -- juros (5%)
    NumInstallments  = 4,          -- número de parcelas
    InstallmentDays  = 7,          -- dias entre parcelas
    PenaltyRate      = 0.15,       -- multa por atraso (15%)
    -- Calote: a cada parcela vencida o sistema tenta debitar a parcela automaticamente
    -- (banco do jogador / cofre da empresa). Sem saldo => multa + parcela perdida.
    -- Ao atingir MaxMissedPayments consecutivas o empréstimo vira 'defaulted': para de
    -- acumular multa, bloqueia novos empréstimos/venda da empresa e só sai quitando tudo.
    AutoDebit         = true,
    MaxMissedPayments = 3,
    CheckInterval    = 300,        -- segundos entre verificações de atraso
    BankerLocation   = vector3(-2962.6, 485.6, 15.7),  -- Paleto Bay bank
    BankerPed        = 'ig_bankman',
    BankerHeading    = 90.0,
}

Config.Flatbed = {
    model    = 'flatbed',
    bedModel = 'inm_flatbed_base',

    -- Animação do operador ao usar controles do flatbed
    animation = {
        dict          = 'amb@world_human_tourist_map@male@base',
        anim          = 'base',
        prop_model    = 'xm_prop_x17_tem_control_01',
        prop_bone     = 28422,
        prop_placement = { -0.01, 0, 0, -20.0, 364.0, 0.0 },
        duration      = 1500,
    },

    -- Posições do bed prop em 3 estados: [0]=recolhido, [1]=recuado, [2]=abaixado
    -- NOTA: offsets estimados baseados no modelo flatbed vanilla — AJUSTAR in-game se necessário
    statePositions = {
        [0] = { pos = {0.0, -3.6, 0.22}, rot = {0.0, 0.0, 0.0} },
        [1] = { pos = {0.0, -7.6, 0.22}, rot = {0.0, 0.0, 0.0} },
        [2] = { pos = {0.0, -7.8, -0.7}, rot = {14.0, 0.0, 0.0} },
    },
}

-- ============================================================
-- NPC DRIVERS (v10.0.0)
-- ============================================================
Config.NpcDrivers = {
    maxDriversPerCompany = 5,
    agencyLocation       = vector3(-179.0, -1320.0, 31.3),
    agencyRadius         = 15.0,
    agencyHeading        = 270.0,
    agencyPedModel       = 's_m_m_trucker_01',
    basePedModel         = 's_m_m_trucker_01',
    -- GP-M04: reduzido de 86400 (24h) → 3600 (1h) para maior dinâmica de contratação
    agencyRefreshSeconds = 3600,
    cronIntervalMinutes  = 5,

    hireCost = {
        junior = 2000,
        pleno  = 6000,
        senior = 15000,
    },

    trainingCost = {
        junior_to_pleno = 5000,
        pleno_to_senior = 12000,
    },
    trainingJobsRequired = {
        junior_to_pleno = 20,
        pleno_to_senior = 50,
    },

    skillEfficiency = {
        junior = 0.80,
        pleno  = 0.95,
        senior = 1.10,
    },

    skillSpeedFactor = {
        junior = 0.80,
        pleno  = 0.95,
        senior = 1.00,
    },

    eventChance = {
        junior = 0.25,
        pleno  = 0.12,
        senior = 0.05,
    },

    satisfaction = {
        startValue            = 80,
        gainPerJob            = 3,
        decayPerDayLowSalary  = 1,
        penaltyDemandIgnored  = 5,
        penaltyEventIgnored   = 10,
        gainDemandGranted     = 8,
        lowThreshold          = 40,
        criticalThreshold     = 20,
    },

    tenureDemands = {
        { days = 15,  type = 'salary_raise',   value = 0.15 },
        { days = 30,  type = 'better_vehicle', value = nil  },
        { days = 60,  type = 'rest_day',       value = nil  },
        { days = 90,  type = 'profit_share',   value = 1000 },
    },
    demandExpiryDays = 3,

    minorEvents = {
        traffic_fine   = { costMin = 150, costMax = 300  },
        minor_accident = { integrityLoss = 10            },
        fuel_over      = { costMin = 100, costMax = 200  },
        delayed        = { extraMinutes = 30             },
    },

    graveEvents = {
        major_accident    = { repairMin = 800, repairMax = 2000 },
        cargo_stolen      = {},
        contraband_caught = { bribeAmount = 3000 },
    },
    graveEventTimerSeconds = 300,

    contraband = {
        reputationPenalty = 10,
        fineAmount        = 5000,
        driverRestSeconds = 86400,
        catchChance = {
            junior = 0.30,
            pleno  = 0.15,
            senior = 0.08,
        },
    },

    reputation = {
        gainPerNormalJob  = 1,
        gainPerLongJob    = 3,
        longJobDistanceKm = 30,
    },

    positionUpdateIntervalMs = 15000,
    blipSprite = 477,
    blipScale  = 0.7,
}

Config.RepoMan = {
    -- Geração de ordens
    PoolInterval        = 1800,      -- segundos entre verificações do pool NPC (30 min)
    MaxNpcOrders        = 5,         -- máximo de ordens NPC disponíveis simultaneamente
    NpcOrderExpiry      = 7200,      -- segundos até expirar ordem NPC (2h)
    LoanOrderExpiry     = 86400,     -- segundos até expirar ordem de loan (24h)
    NpcMissionWeights   = { simple = 70, npc_hostile = 30 },

    -- Pagamento
    PaymentRate         = 0.15,      -- 15% do vehicle_value
    CompanyFeeRate      = 0.20,      -- empresa recebe 20% do pagamento do agente
    TypeMultipliers     = {
        simple      = 1.0,
        npc_hostile = 1.5,
        pvp         = 2.0,
        stealth     = 2.5,
    },

    -- Veículos (lookup de valor por modelo)
    DefaultVehicleValue = 50000,
    VehicleValues = {
        flatbed     = 80000,
        hauler      = 120000,
        phantom     = 150000,
        mule        = 60000,
        bison       = 45000,
    },

    -- Veículos NPC (pool)
    NpcVehicles = {
        { model = 'mule',    label = 'Mule',    value = 60000 },
        { model = 'bison',   label = 'Bison',   value = 45000 },
        { model = 'flatbed', label = 'Flatbed', value = 80000 },
    },

    -- Zonas NPC (coordenadas de localização dos veículos NPC no mapa)
    NpcZones = {
        { name = 'Porto de LS',  coords = vector3(-670.0, -1450.0, 5.0),  radius = 80.0 },
        { name = 'Boneyard',     coords = vector3(1660.0, 3167.0, 41.0),  radius = 60.0 },
        { name = 'Sandy Shores', coords = vector3(1820.0, 3692.0, 34.0),  radius = 70.0 },
        { name = 'Paleto Bay',   coords = vector3(-183.0, 6317.0, 31.0),  radius = 50.0 },
        { name = 'Grapeseed',    coords = vector3(1696.0, 4789.0, 42.0),  radius = 60.0 },
    },

    -- Impound (entrega — Sub-spec 2)
    ImpoundLocation     = vector3(400.0, -1640.0, 29.0),
    ImpoundHeading      = 90.0,

    -- Gameplay (Sub-spec 2)
    vehicleModels = {
        sedan  = { 'sultan', 'premier', 'asea', 'stratum' },
        suv    = { 'granger', 'cavalcade', 'patriot' },
        truck  = { 'bison', 'bobcatxl', 'sandking2' },
        sport  = { 'feltzer2', 'sentinel', 'schafter2' },
    },
    flatbedSpawnDistance   = 55.0,
    impoundRadius          = 15.0,
    missionTimeout         = 900,
    stealthDetectionRadius = 15.0,
    pvpBlipDuration        = 300,
    npcGuardModel          = 's_m_m_security_01',
    npcGuardCount          = { min = 2, max = 4 },
    npcGuardRadius         = 8.0,
    npcLeashRadius         = 80.0,
}

-- =======================================
-- EMPRESA — PROGRESSÃO DE NÍVEL
-- =======================================
-- 30 níveis. xpRequired = XP acumulado para atingir este nível.
-- vehicles = slots de veículos, members = membros máximos, bonus = multiplicador de pagamento
-- AVISO: Config.CompanyXpPerDelivery não deve exceder 50 (gap mínimo entre nível 1 e 2).
-- Se aumentado, ajuste AddXP — o loop já suporta multi-level-up.
-- GP-H04: bonus reescalado de max 1.06 (6%) → max 1.25 (25%).
-- Curva de aceleração: lento no início (incentivo a criar empresa), acelerado nos últimos 10.
-- Lv 1-10: 0% → 5% | Lv 11-20: 6% → 15% | Lv 21-30: 17% → 25%
Config.CompanyLevels = {
    -- level  xpRequired  vehicles  members  bonus
    { level = 1,  xpRequired = 0,     vehicles = 2, members = 5,  bonus = 1.00 },
    { level = 2,  xpRequired = 50,    vehicles = 2, members = 6,  bonus = 1.00 },
    { level = 3,  xpRequired = 150,   vehicles = 2, members = 7,  bonus = 1.01 },
    { level = 4,  xpRequired = 300,   vehicles = 2, members = 7,  bonus = 1.02 },
    { level = 5,  xpRequired = 500,   vehicles = 3, members = 8,  bonus = 1.02 },
    { level = 6,  xpRequired = 750,   vehicles = 3, members = 9,  bonus = 1.03 },
    { level = 7,  xpRequired = 1050,  vehicles = 3, members = 9,  bonus = 1.03 },
    { level = 8,  xpRequired = 1400,  vehicles = 3, members = 10, bonus = 1.04 },
    { level = 9,  xpRequired = 1800,  vehicles = 3, members = 11, bonus = 1.04 },
    { level = 10, xpRequired = 2250,  vehicles = 4, members = 12, bonus = 1.05 },
    { level = 11, xpRequired = 2750,  vehicles = 4, members = 12, bonus = 1.06 },
    { level = 12, xpRequired = 3300,  vehicles = 4, members = 13, bonus = 1.07 },
    { level = 13, xpRequired = 3900,  vehicles = 4, members = 13, bonus = 1.08 },
    { level = 14, xpRequired = 4550,  vehicles = 4, members = 14, bonus = 1.09 },
    { level = 15, xpRequired = 5250,  vehicles = 4, members = 15, bonus = 1.10 },
    { level = 16, xpRequired = 6000,  vehicles = 4, members = 15, bonus = 1.11 },
    { level = 17, xpRequired = 6800,  vehicles = 4, members = 16, bonus = 1.12 },
    { level = 18, xpRequired = 7650,  vehicles = 4, members = 16, bonus = 1.13 },
    { level = 19, xpRequired = 8550,  vehicles = 4, members = 17, bonus = 1.14 },
    { level = 20, xpRequired = 9500,  vehicles = 5, members = 17, bonus = 1.15 },
    { level = 21, xpRequired = 10500, vehicles = 5, members = 18, bonus = 1.17 },
    { level = 22, xpRequired = 11550, vehicles = 5, members = 18, bonus = 1.18 },
    { level = 23, xpRequired = 12650, vehicles = 5, members = 18, bonus = 1.20 },
    { level = 24, xpRequired = 13800, vehicles = 5, members = 19, bonus = 1.21 },
    { level = 25, xpRequired = 15000, vehicles = 5, members = 19, bonus = 1.22 },
    { level = 26, xpRequired = 16250, vehicles = 5, members = 19, bonus = 1.23 },
    { level = 27, xpRequired = 17550, vehicles = 5, members = 20, bonus = 1.24 },
    { level = 28, xpRequired = 18900, vehicles = 5, members = 20, bonus = 1.24 },
    { level = 29, xpRequired = 20300, vehicles = 5, members = 20, bonus = 1.25 },
    { level = 30, xpRequired = 21750, vehicles = 5, members = 20, bonus = 1.25 },
}

-- XP concedido à empresa por entrega concluída de um membro
Config.CompanyXpPerDelivery = 50

-- ============================================================
-- SIMULAÇÃO DE VIAGEM (EuroTruck-inspired)
-- ============================================================

Config.TruckSimulation = {
    -- Modelos que ativam o HUD e as threads de simulação
    -- GP-L03: adicionados hauler2, mule2, mule3, packer — usados em deliveryVehicle
    -- de TradePoints e outros pontos do resource mas sem HUD antes desta correção.
    TruckModels = {
        'flatbed', 'hauler', 'hauler2', 'phantom', 'mule', 'mule2', 'mule3', 'bison', 'packer',
    },

    HUD = {
        Enabled  = true,           -- false = desativa display; sistemas continuam rodando e exports funcionam
        Position = 'bottom-left',  -- bottom-left | bottom-right | top-left | top-right
        Scale    = 1.0,
    },

    Fuel = {
        ConsumptionRate    = 0.015,  -- % de tanque por segundo em velocidade normal
        LoadedMultiplier   = 1.4,    -- consumo extra com job ativo
        LowFuelThreshold   = 20.0,   -- % para alerta no HUD
        SyncInterval       = 30000,  -- ms entre syncs periódicos com servidor
        FuelPricePerUnit   = 20,     -- $ por % de tanque abastecido
        TankCapacityGTA    = 65.0,   -- valor máximo do nativo SetVehicleFuelLevel (0–65.0 no GTA base)
        -- GP-C03: postos de combustível mapeados em rotas principais de caminhão
        GasStations = {
            { coords = vector3(44.24,    -1741.16, 29.42), name = 'Forum Dr',      radius = 6.0 },
            { coords = vector3(1207.50,  -1402.14, 35.23), name = 'La Mesa',       radius = 6.0 },
            { coords = vector3(-70.23,   -1761.27, 29.53), name = 'Olympic Fwy',   radius = 6.0 },
            { coords = vector3(-269.52,  -1433.98, 31.09), name = 'Strawberry',    radius = 6.0 },
            { coords = vector3(1183.88,  -328.51,  68.35), name = 'Route 68',      radius = 6.0 },
            { coords = vector3(48.19,    2778.35,  57.95), name = 'Route 68 N',    radius = 6.0 },
            { coords = vector3(1209.37,  2660.27,  37.90), name = 'Sandy Shores',  radius = 6.0 },
            { coords = vector3(-2557.32, 2332.07,  33.37), name = 'Chumash',       radius = 6.0 },
            { coords = vector3(-89.25,   6420.35,  31.49), name = 'Paleto Bay',    radius = 6.0 },
            { coords = vector3(2005.73,  3773.23,  32.40), name = 'Sandy S. Hwy',  radius = 6.0 },
            { coords = vector3(-699.21,  -932.62,  19.22), name = 'Alta St',       radius = 6.0 },
        },
    },

    Fatigue = {
        IncreaseRate      = 0.02,  -- % por segundo dirigindo
        RestoreRate       = 0.5,   -- % por segundo em parada de descanso
        RestDuration      = 1.2,   -- segundos de barra por % de fadiga (80% fadiga = 96s de barra)
        WarnThreshold          = 50.0,
        HeavyThreshold         = 75.0,
        CriticalThreshold      = 90.0,
        MinSpeedForSleep       = 5.0,   -- m/s mínimo para disparar perda de controle (evita griefing parado)
        TimecycleWarnStrength  = 0.3,   -- intensidade do efeito visual em WarnThreshold (0.0–1.0)
        TimecycleHeavyStrength = 0.6,   -- intensidade do efeito visual em HeavyThreshold (0.0–1.0)
        -- GP-C03: paradas de descanso em estacionamentos e áreas de serviço nas rodovias
        RestStops = {
            { coords = vector3(1727.70,  3756.02,  34.87), name = 'Sandy Shores WS',  radius = 10.0 },
            { coords = vector3(578.30,   2787.97,  42.42), name = 'Harmony WS',        radius = 10.0 },
            { coords = vector3(1719.67,  4789.32,  41.98), name = 'Grapeseed WS',      radius = 10.0 },
            { coords = vector3(-183.0,   6317.0,   31.0 ), name = 'Paleto Bay WS',     radius = 10.0 },
            { coords = vector3(2672.04,  1826.19,  24.11), name = 'Alamo Sea WS',      radius = 10.0 },
            { coords = vector3(-1604.75, -1037.73, 13.17), name = 'Coastal WS',        radius = 10.0 },
            { coords = vector3(153.81,   -3214.60,  4.93), name = 'Porto Sul WS',      radius = 12.0 },
        },
    },

    Cargo = {
        -- v20.6.4: Tolerância aumentada e proteção contra frenagens normais
        -- ImpactThreshold: 10.0 m/s (~36 km/h de choque em 500ms) para colisão real
        -- CatastrophicThreshold: 18.0 m/s (~65 km/h em 500ms) para impacto violento/muro
        ImpactThreshold       = 10.0,   -- m/s de queda de velocidade/tick para considerar impacto
        CatastrophicThreshold = 18.0,   -- m/s para impacto catastrófico imediato
        ImpactDamageBase      = 4.0,    -- % base de integridade perdida por colisão
        ImpactDamageMax       = 15.0,   -- % máxima por colisão violenta
        ImpactDamage          = 5.0,    -- Fallback de compatibilidade
        ImpactCooldown        = 2500,   -- ms de intervalo mínimo entre danos por impacto
        SpeedDamageRate       = 0.002,  -- % por segundo acima do SpeedLimit
        SpeedLimit            = 36.0,   -- m/s (~130 km/h de limite rodoviário seguro)
        MinPaymentRate        = 0.10,   -- pagamento mínimo (10%) se integridade = 0%
    },
}

Config.FleetUpgrades = {
    anti_sleep = {
        label       = 'Sistema Anti-Sono (ADAS)',
        price       = 150000,
        description = 'Freio automático ao detectar fadiga crítica do motorista.',
    },
}

-- ============================================================
-- ADR CERTIFICATIONS (v11.0.0)
-- ============================================================
Config.Adr = {
    -- GP-M03: deslocado ~30m do terminal_a1 (361.62,-2541.45) para evitar
    -- sobreposição de ox_target com o ponto de carregamento da indústria.
    ExaminerLocation = vector3(330.0, -2530.0, 6.0),
    ExaminerPed      = 's_m_m_trucker_01',
    ExaminerHeading  = 90.0,
    ExaminerRadius   = 5.0,

    ValiditySeconds      = 30 * 86400,   -- 2592000
    RetryCooldownSeconds = 1800,

    ExamCost = {
        flammable_liquid = 5000,
        flammable_gas    = 6000,
        toxic            = 8000,
        corrosive        = 8000,
        explosive        = 15000,
        environmental    = 6000,
    },

    RenewalCost = {
        flammable_liquid = 3000,
        flammable_gas    = 3600,
        toxic            = 4800,
        corrosive        = 4800,
        explosive        = 9000,
        environmental    = 3600,
    },

    TypeLabels = {
        flammable_liquid = 'Líquidos Inflamáveis',
        flammable_gas    = 'Gases Inflamáveis',
        toxic            = 'Substâncias Tóxicas',
        corrosive        = 'Substâncias Corrosivas',
        explosive        = 'Explosivos',
        environmental    = 'Perigosas ao Meio Ambiente',
    },

    -- Banco de perguntas (com gabarito) movido para server/adr_questions.lua (AdrExamBank, só servidor)
}

-- ================================================
-- PROPRIEDADE DE INDÚSTRIAS
-- ================================================
Config.IndustryOwnership = {
    PurchasePriceMultiplier = 10,    -- preço = basePrice * productionPerHour * mult
    OperationalCostPerCycle = 500,   -- deducted da empresa por ciclo de produção (server)
    OwnerProfitPercent      = 0.15,  -- 15% de cada venda vai para a empresa dona
    MaxOwnedPerCompany      = 3,     -- máximo de indústrias por empresa
}

-- ================================================
-- CONVOY SYSTEM (Fase 3A — Multiplayer)
-- ================================================
Config.Party = {
    maxSize                  = 2,        -- máximo de membros por party (Dupla: Motorista + Ajudante)
    cbRadioKey               = 'Z',      -- tecla para abrir input do rádio CB
    cbRadioRange             = 500.0,    -- metros — fora do range não recebe mensagem
    cbMessageDuration        = 8,        -- segundos antes de sumir do HUD
    gracePeriod              = 180,      -- segundos de grace period ao desconectar
    bonusMultiplier          = 1.5,      -- multiplicador de pagamento em convoy completo
    positionBroadcastInterval = 3000,   -- ms entre updates de blip de posição
}

-- ============================================================
-- FASE 3B: Illegal Deliveries
-- ============================================================

Config.IllegalJobs = {

    SeizeRange = 50.0,  -- distância máxima (m) para apreensão de carga ilegal (staff vs motorista)

    -- Pontos de contato físicos no mapa (NPCs clandestinos)
    contacts = {
        {
            id     = 'contact_docks',
            label  = 'Contato nos Docas',
            area   = 'Porto',
            coords = vector3(-1087.0, -2717.0, 14.0),
            radius = 5.0,
            cargo  = { 'contraband', 'weapons', 'drugs' },
        },
        {
            id     = 'contact_boneyard',
            label  = 'Contato no Cemitério de Aviões',
            area   = 'Cemitério de Aviões',
            coords = vector3(2010.0, 4773.0, 42.0),
            radius = 5.0,
            cargo  = { 'contraband', 'minerals' },
        },
        {
            id     = 'contact_paleto',
            label  = 'Contato em Paleto Bay',
            area   = 'Paleto Bay',
            coords = vector3(-448.0, 6012.0, 32.0),
            radius = 5.0,
            cargo  = { 'animals', 'minerals', 'contraband' },
        },
        {
            id     = 'contact_sandy',
            label  = 'Contato em Sandy Shores',
            area   = 'Sandy Shores',
            coords = vector3(1972.0, 3812.0, 33.0),
            radius = 5.0,
            cargo  = { 'drugs', 'weapons' },
        },
        {
            id     = 'contact_ls_south',
            label  = 'Contato no Sul de LS',
            area   = 'Sul de Los Santos',
            coords = vector3(128.0, -1950.0, 21.0),
            radius = 5.0,
            cargo  = { 'contraband', 'animals', 'drugs' },
        },
    },

    -- Pontos de entrega clandestinos
    deliveries = {
        {
            id      = 'delivery_warehouse',
            area    = 'Armazém Industrial',
            coords  = vector3(978.0, -2196.0, 30.0),
            radius  = 10.0,
            accepts = { 'contraband', 'weapons', 'drugs' },
        },
        {
            id      = 'delivery_farm',
            area    = 'Fazenda Abandonada',
            coords  = vector3(2502.0, 4139.0, 38.0),
            radius  = 10.0,
            accepts = { 'animals', 'minerals', 'contraband' },
        },
        {
            id      = 'delivery_quarry',
            area    = 'Pedreira',
            coords  = vector3(816.0, 2966.0, 42.0),
            radius  = 10.0,
            accepts = { 'minerals', 'contraband' },
        },
        {
            id      = 'delivery_port',
            area    = 'Porto Clandestino',
            coords  = vector3(-350.0, -2800.0, 6.0),
            radius  = 10.0,
            accepts = { 'drugs', 'weapons', 'animals' },
        },
    },

    -- Multiplicadores de pagamento por tipo de carga (base = dist_km × distanceMultiplier)
    paymentMultipliers = {
        contraband = 2.0,
        animals    = 2.5,
        minerals   = 2.3,
        weapons    = 3.0,
        drugs      = 2.8,
    },

    -- Multa aplicada ao motorista quando a carga é apreendida pela polícia
    seizureFines = {
        contraband = 5000,
        animals    = 8000,
        minerals   = 6000,
        weapons    = 15000,
        drugs      = 12000,
    },

    -- Labels usados nos alertas de SALA / LSPD
    alertLabels = {
        contraband = 'Contrabando',
        animals    = 'Animais Silvestres',
        minerals   = 'Minerais Ilegais',
        weapons    = 'Armamentos',
        drugs      = 'Entorpecentes',
    },

    -- Tipos de alta prioridade recebem prefixo [LSPD ⚠] e alert para SALA também
    highPriorityTypes = { 'weapons', 'drugs' },

    -- Tipos que geram alerta para SALA (além de LSPD)
    salaAlertTypes = { 'animals', 'minerals', 'weapons', 'drugs' },

    -- Tipos de carga ilegal que exigem certificação ADR
    adrRequired = {
        weapons = 'explosive',
    },
}

-- ============================================================
-- FASE 5: FORKLIFT
-- ============================================================

Config.Forklift = {

    -- Custo e reembolso de aluguel
    RentalCost   = 500,   -- $500 debitado do banco ao alugar
    RefundAmount = 250,   -- $250 devolvidos ao retornar no spawn (raio 15m)

    -- Modelo do forklift e dos pallets
    ForkliftModel = 'forklift',
    PalletModel   = 'prop_pallet_05a',

    -- Parâmetros de detecção de carregamento
    LoadDetectRadius = 3.0,   -- metros: distância máxima pallet→boot
    BootDoorRatio    = 0.75,  -- GetVehicleDoorAngleRatio >= este valor

    -- -------------------------------------------------------
    -- MODO 1: Trade Points (jobs standalone)
    -- -------------------------------------------------------
    TradePoints = {
        {
            id              = 'walker_logistics',
            name            = 'Walker Logistics',
            coords          = vector3(153.81, -3214.60, 4.93),
            npcCoords       = vector4(156.0, -3211.0, 4.93, 180.0),
            forkliftSpawn   = vector4(148.0, -3208.0, 4.93, 90.0),
            palletSpawns    = {
                vector4(158.0, -3220.0, 4.93, 0.0),
                vector4(161.0, -3220.0, 4.93, 0.0),
                vector4(164.0, -3220.0, 4.93, 0.0),
                vector4(158.0, -3224.0, 4.93, 0.0),
                vector4(161.0, -3224.0, 4.93, 0.0),
            },
            deliveryVehicle = 'benson',
            deliveryStart   = vector4(130.0, -3190.0, 4.93, 180.0),
            deliveryEnd     = vector4(153.0, -3215.0, 4.93, 180.0),
            maxPallets      = 5,
            basePay         = 500,
            timeLimit       = 180,
        },
        {
            id              = 'pacific_shipyard',
            name            = 'Pacific Shipyard',
            coords          = vector3(739.3, -2869.6, 0.9),
            npcCoords       = vector4(742.0, -2866.0, 0.9, 90.0),
            forkliftSpawn   = vector4(735.0, -2872.0, 0.9, 270.0),
            palletSpawns    = {
                vector4(748.0, -2875.0, 0.9, 0.0),
                vector4(751.0, -2875.0, 0.9, 0.0),
                vector4(754.0, -2875.0, 0.9, 0.0),
                vector4(748.0, -2879.0, 0.9, 0.0),
                vector4(751.0, -2879.0, 0.9, 0.0),
            },
            deliveryVehicle = 'mule2',
            deliveryStart   = vector4(720.0, -2850.0, 0.9, 90.0),
            deliveryEnd     = vector4(740.0, -2870.0, 0.9, 90.0),
            maxPallets      = 5,
            basePay         = 550,
            timeLimit       = 180,
        },
        -- v20: Porto Sul — adicionado a partir dos coords do oForklift (Doca Sul)
        {
            id              = 'porto_sul',
            name            = 'Porto Sul — Doca A',
            coords          = vector3(-424.25, -2789.89, 5.51),
            npcCoords       = vector4(-424.25, -2789.89, 5.51, 320.31),
            forkliftSpawn   = vector4(-430.65, -2761.70, 5.43, 178.58),
            palletSpawns    = {
                vector4(-436.25, -2761.01, 5.11,  62.48),
                vector4(-440.48, -2795.57, 6.41, -45.98),
                vector4(-465.41, -2814.51, 5.00, 134.19),
                vector4(-476.87, -2791.77, 6.02,  46.62),
                vector4(-503.65, -2858.54, 6.30, -45.90),
            },
            palletPool      = 'porto_sul',          -- usa props visuais variados (PalletModels abaixo)
            deliveryVehicle = 'mule3',
            deliveryStart   = vector4(-487.38, -2816.10, 6.22, 317.48),
            deliveryEnd     = vector4(-490.60, -2819.39, 5.99, 317.48),
            maxPallets      = 5,
            basePay         = 620,
            timeLimit       = 200,
        },
    },

    -- -------------------------------------------------------
    -- POOL DE PROPS DE PALETES por TradePoint (v20)
    -- Quando um TradePoint define palletPool, o client escolhe
    -- aleatoriamente um modelo desta lista para cada pallet,
    -- adicionando identidade visual à carga.
    -- -------------------------------------------------------
    PalletModels = {
        porto_sul = {
            'ex_prop_crate_tob_sc',          -- Álcool
            'ba_prop_battle_crate_tob_bc',   -- Álcool
            'prop_boxpile_06a',              -- Encomendas
            'vw_prop_vw_crate_01a',          -- Cassino
            'sm_prop_smug_crate_m_tobacco',  -- Tabaco
            'ex_prop_crate_clothing_sc',     -- Moda
            'v_ind_meatdogpack',             -- Alimentos
            'sm_prop_smug_crate_m_medical',  -- Médico
            'ex_prop_crate_jewels_sc',       -- Joias
            'ex_prop_crate_wlife_sc',        -- Marfim
            'xm3_prop_xm3_cem_bags_01a',     -- Cimento
            'ex_prop_crate_med_sc',          -- Suprimentos Médicos
            'ba_prop_battle_crate_biohazard_bc', -- Químicos
            'ex_prop_crate_furjacket_bc',    -- Roupas
            'ex_prop_crate_bull_sc_02',      -- Peças
            'sm_prop_smug_crate_m_antiques', -- Arte
            'ba_prop_battle_crate_m_jewellery', -- Joalheria
            'ex_prop_crate_elec_bc',         -- Multimídia
            'prop_boxpile_09a',              -- Cerveja
            'sf_prop_sf_slot_pallet_01a',    -- Arcade
            'prop_pallet_05a',               -- Genérico (fallback)
        },
    },

    -- -------------------------------------------------------
    -- MODO 2: Industry Spawns (forklift para delivery jobs)
    -- -------------------------------------------------------
    IndustrySpawns = {
        ['porto_a1'] = vector4(361.0, -2545.0, 5.74, 270.0),
    },
}

-- ============================================================
-- SKILL TREE (v13.0.0)
-- ============================================================

Config.Skills = {
    BonusPerLevel     = 0.02,   -- +2% por nível de skill ativo (ex: lv3 = +6%)
    DistanceThreshold = 10.0,   -- km mínimos para Distance ser ativada
    -- GP-C02: reduzido de 5000 → 1500. Com maxPayment=8000 e fórmula corrigida,
    -- jobs de alta carga (Eletrônicos×4, dist. longa) atingem ~$3000-$5000+.
    -- O threshold de 1500 ativa a skill Valuable para jobs de médio-alto valor.
    ValuableThreshold = 1500,   -- $ mínimos no basePayment para Valuable ser ativada
    FragileThreshold  = 85,     -- % mínimos de integridade entregue para Fragile ser ativada
}

-- ============================================================
-- CARGO THEFT (v14.0.0)
-- ============================================================

Config.CargoTheft = {
    VulnerableDelay  = 30,       -- segundos parado sem motorista para ativar vulnerabilidade
    TheftDuration    = 20,       -- segundos do progress bar de roubo
    TheftRange       = 15.0,     -- distância máxima entre caminhões para transferência (metros)
    TheftBonus       = 0.25,     -- +25% sobre base_payment para carga roubada entregue
    GpsTrackerPrice  = 5000,     -- $ para instalar GPS tracker num veículo de empresa
    VulnerableBlip   = true,     -- mostrar blip para todos os jogadores quando cargo é vulnerável
    PoliceJob        = 'police', -- job dos policiais que recebem alertas de roubo
    PoliceZones      = {
        { name = 'Porto',           coords = vec3(361.0,   -2545.0,  5.7),   radius = 300.0 },
        { name = 'Zona Industrial', coords = vec3(100.0,   -1700.0, 29.0),   radius = 400.0 },
        { name = 'Aeroporto',       coords = vec3(-1037.0, -2737.0, 13.0),   radius = 500.0 },
        { name = 'Centro',          coords = vec3(195.0,    -930.0, 30.0),   radius = 400.0 },
        { name = 'Los Santos Sul',  coords = vec3(80.0,    -1620.0, 29.0),   radius = 350.0 },
    },
}

-- ============================================================
-- ANTI-CHEAT (v15.0.0)
-- ============================================================

Config.AntiCheat = {
    Enabled = true,

    -- Raio máximo (metros) entre jogador e destino ao completar job.
    -- 80m cobre trailers compridos estacionados próximos à doca.
    DestinationRadius = 80.0,

    -- Velocidade MÁXIMA possível de um caminhão em km/h.
    -- Usado para calcular o tempo MÍNIMO de viagem.
    -- Se o player entregou mais rápido que isso → teleporte → bloqueado.
    MaxSpeedKmh = 120.0,

    -- Tempo MÍNIMO absoluto em segundos para qualquer entrega (evita entregas instantâneas em rotas curtas)
    MinTravelTimeSeconds = 25,

    -- Cooldowns em segundos por evento (0 = sem cooldown)
    RateLimits = {
        acceptJob             = 3,
        completeJob           = 5,
        completeContractStop  = 2,
        startCargoTheft       = 10,
        completeCargoTheft    = 5,
        depositMoney          = 2,
        withdrawMoney         = 2,
    },
}

Config.CrudeOil = {
    -- Refinery locations for GPS and ox_target delivery zones.
    -- ⚠ REQUIRED: Fill in standard_1 coords BEFORE Task 8 end-to-end test.
    -- To find: go to Sandy Shores refinery NPC in-game, open F8 console, run:
    --   print(GetEntityCoords(PlayerPedId()))
    Refineries = {
        -- GP-C04: coords (0,0,0) causam rejeição pelo anticheat com mensagem "Posição inválida".
        -- Coordenada abaixo aponta para a Ron Alternates Wind Farm (refinaria vanilla do GTA V
        -- em Sandy Shores). Ajuste in-game se necessário com print(GetEntityCoords(PlayerPedId())).
        { id = 'standard_1',   name = 'Refinaria Sandy Shores',        coords = vec4(2547.15, 2593.08, 37.94, 270.0) },
        { id = 'premium_1',    name = 'Refinaria Premium',             coords = vec4(-1094.20, -2700.10, 14.00, 0.0) },
        { id = 'industrial_1', name = 'Terminal Industrial — Porto LS', coords = vec4(-267.00, -2780.00, 6.00, 90.0) },
    },
    UnloadTimePerBarrel = 2000, -- ms per barrel at refinery
    DeliveryRadius      = 6.0,  -- meters for ox_target at refinery
}

-- ============================================================
-- SHOP STOCK ECOSYSTEM (v16.0.0)
-- Integração com ox_inventory — estoque real nas lojas
-- ============================================================

Config.ShopStock = {
    Enabled              = true,
    CheckInterval        = 300000,   -- 5 min entre verificações de estoque baixo
    NpcFailsafeDelay     = 1800,     -- 30 min sem estoque → NPC ressuprimento automático
    NpcFailsafeAmount    = 25,       -- unidades adicionadas pelo NPC failsafe
    ContractExpiryMinutes = 120,     -- contratos de ressuprimento expiram em 2h
    ContractPaymentPerUnit = 15,     -- $/unidade base para pagamento do caminhoneiro

    -- Mapeia tipos de loja do ox_inventory → itens rastreados + tipo de indústria vinculada
    -- Apenas itens listados aqui terão estoque controlado. Os demais permanecem infinitos.
    -- locations: coords do ox_inventory/data/shops.lua (para GPS de entrega)
    Shops = {
        General = {
            name = 'Conveniência 24/7',
            locations = {
                vec3(25.7, -1347.3, 29.49),
                vec3(-3038.71, 585.9, 7.9),
                vec3(-3241.47, 1001.14, 12.83),
                vec3(1728.66, 6414.16, 35.03),
                vec3(1697.99, 4924.4, 42.06),
                vec3(1961.48, 3739.96, 32.34),
                vec3(547.79, 2671.79, 42.15),
                vec3(2679.25, 3280.12, 55.24),
                vec3(2557.94, 382.05, 108.62),
                vec3(373.55, 325.56, 103.56),
            },
            items = {
                { name = 'burger', maxStock = 150, minThreshold = 15, reorderQty = 40, pricePerUnit = 12, linkedType = 'food' },
                { name = 'water',  maxStock = 200, minThreshold = 20, reorderQty = 50, pricePerUnit = 10, linkedType = 'food' },
                { name = 'cola',   maxStock = 200, minThreshold = 20, reorderQty = 50, pricePerUnit = 10, linkedType = 'food' },
            },
        },
        Liquor = {
            name = 'Loja de Bebidas',
            locations = {
                vec3(1135.808, -982.281, 46.415),
                vec3(-1222.915, -906.983, 12.326),
                vec3(-1487.553, -379.107, 40.163),
                vec3(-2968.243, 390.910, 15.043),
                vec3(1166.024, 2708.930, 38.157),
                vec3(1392.562, 3604.684, 34.980),
                vec3(-1393.409, -606.624, 30.319),
            },
            items = {
                { name = 'water',  maxStock = 150, minThreshold = 15, reorderQty = 40, pricePerUnit = 10, linkedType = 'food' },
                { name = 'cola',   maxStock = 150, minThreshold = 15, reorderQty = 40, pricePerUnit = 10, linkedType = 'food' },
                { name = 'burger', maxStock = 100, minThreshold = 10, reorderQty = 30, pricePerUnit = 12, linkedType = 'food' },
            },
        },
    },

    -- =============================================================
    -- SISTEMA DE CARGA FÍSICA (v19.0)
    -- =============================================================

    CarryProps = {
        small_box  = { model = 'prop_cs_cardbox_01',  bone = 57005, offset = vec3(0.1, 0.0, -0.16), rot = vec3(0.0, 270.0, 60.0),  anim = { dict = 'anim@heists@box_carry@', clip = 'idle' } },
        medium_box = { model = 'prop_box_ammo04a',     bone = 57005, offset = vec3(0.15, 0.05, 0.0), rot = vec3(-50.0, 0.0, 0.0),    anim = { dict = 'anim@heists@box_carry@', clip = 'idle' } },
        barrel     = { model = 'prop_barrel_02a',       bone = 57005, offset = vec3(0.2, 0.0, -0.1),  rot = vec3(0.0, 270.0, 60.0),   anim = { dict = 'missfinale_c2ig_11',     clip = 'pushcar_offcliff_f' } },
        sack       = { model = 'prop_cs_sack_01',       bone = 57005, offset = vec3(0.15, 0.1, 0.0),  rot = vec3(-50.0, 0.0, 0.0),    anim = { dict = 'anim@heists@box_carry@', clip = 'idle' } },
    },

    CargoToCarryType = {
        ['default']        = 'small_box',
        ['electronics']    = 'medium_box',
        ['crude_oil']      = 'barrel',
        ['grain']          = 'sack',
        ['food']           = 'small_box',
        ['construction']   = 'medium_box',
        ['chemicals']      = 'barrel',
        ['textiles']       = 'sack',
    },

    ManualLoading = {
        Enabled       = true,
        ManualMaxQty  = 5,
        PickupDuration  = 3000,
        DepositDuration = 2000,
        DepositDistance  = 3.0,
        SpeedReduction  = true,
    },

    ParcelDelivery = {
        Enabled     = true,
        DepotCoords = vector4(68.77, -1399.93, 29.37, 140.0),
        DepotNPC    = 's_m_m_postal_02',
        DepotBlip   = { sprite = 478, color = 5, scale = 0.7, label = 'Depósito de Encomendas' },
        -- GP-M05: MinLevel=0 mantido (emprego de iniciante), MaxLevel elevado de 3 → 12.
        -- Cria progressão: iniciante faz van, veterano migra para trucking.
        MinLevel    = 0,
        MaxLevel    = 12,
        BasePayment = { min = 80, max = 180 },
        Cooldown    = 90,
        MaxDistance  = 800,
        -- Raios server-side (ox_lib callbacks) — fail-closed se ped inválido
        StopRadius   = 15.0,
        DepotRadius  = 20.0,
        DeliveryPoints = {
            vector4(215.12, -810.17, 29.73, 0.0),
            vector4(-703.56, -864.65, 23.35, 0.0),
            vector4(112.30, -1034.27, 28.36, 0.0),
            vector4(-34.57, -1461.68, 31.28, 0.0),
            vector4(238.46, -776.74, 30.67, 0.0),
            vector4(-1222.89, -907.59, 12.32, 0.0),
            vector4(28.16, -1339.84, 29.50, 0.0),
            vector4(372.77, 326.72, 103.57, 0.0),
        },

        -- ============================================================
        -- MULTI-STOP ROUTES (integração nek_deliveryjob)
        -- Cada rota define N paradas sequenciais. Pagamento escala:
        --   1 parada = 1.0x  |  3 paradas = 2.0x  |  4 = 2.8x  |  5 = 3.5x
        -- DeliveryPoints acima é mantido como fallback (rota aleatória 1-stop).
        -- ============================================================
        Routes = {
            [1] = {
                label = 'Rota Sul',
                icon  = 'fa-solid fa-route',
                stops = {
                    vector4(215.12,   -810.17,  29.73,  0.0),
                    vector4(112.30,  -1034.27,  28.36,  0.0),
                    vector4(-34.57,  -1461.68,  31.28,  0.0),
                },
            },
            [2] = {
                label = 'Rota Oeste',
                icon  = 'fa-solid fa-map-location-dot',
                stops = {
                    vector4(-703.56,  -864.65,  23.35,   0.0),
                    vector4(-1222.89, -907.59,  12.32,   0.0),
                    vector4(-546.25,  -200.78,  37.00,  90.0),
                    vector4(-232.76,  -152.38,  39.00, 180.0),
                },
            },
            [3] = {
                label = 'Rota Norte',
                icon  = 'fa-solid fa-truck-fast',
                stops = {
                    vector4(238.46,  -776.74,  30.67,   0.0),
                    vector4(372.77,   326.72, 103.57,   0.0),
                    vector4(28.16,  -1339.84,  29.50,   0.0),
                },
            },
        },

        -- Webhook opcional (Discord) para log de entregas
        Webhook = {
            Enabled       = false,
            -- SEGURANÇA: este arquivo é shared (visível/baixável por clientes). Nunca cole a URL aqui;
            -- defina no server.cfg:  set aurp_trucker_parcel_webhook "https://discord.com/api/webhooks/..."
            -- (usar `set`, NÃO `setr`). Só server/services/parcel_service.lua lê o convar.
            CommunityName = 'AURP Trucker — Entregas',
            Color         = {
                Start    = 3066993,   -- verde
                Complete = 5763719,   -- azul
                Cancel   = 15158332,  -- vermelho
            },
        },
    },
}

-- ============================================================
-- CONTAINER HANDLER (v20 — integração oConteneur)
-- Handler portuário com mecânica de grua (bone frame_2).
-- Job de loop standalone: sem tabela DB, pagamento via
-- lib.callback com validação de proximidade server-side.
-- NPC localizado no Terminal A2 (Buccaneer Way).
-- ============================================================
Config.ContainerHandler = {
    Enabled = true,

    -- Veículo e referência do bone da grua
    HandlerModel = 'handler',
    CraneBone    = 'frame_2',
    HandlerHash  = 444583674,  -- GetHashKey('handler') — usado no client para identificar o veículo

    -- Modelo do contêiner e cargo types (15 tipos, traduzidos do oConteneur)
    ContainerModel = 'prop_contr_03b_ld',
    CargoTypes = {
        { name = 'Eletrônicos'             },
        { name = 'Materiais de Construção' },
        { name = 'Vidro'                   },
        { name = 'Cilindros Pressurizados' },
        { name = 'Ferramentas'             },
        { name = 'Peças Mecânicas'         },
        { name = 'Tecidos'                 },
        { name = 'Mercadorias Gerais'      },
        { name = 'Artigos Farmacêuticos'   },
        { name = 'Estatuetas'              },
        { name = 'Joias'                   },
        { name = 'Alimentos'               },
        { name = 'Materiais Industriais'   },
        { name = 'Equipamentos Médicos'    },
        { name = 'Games e Eletrônicos'     },
    },

    -- NPC e spawn do Handler
    NpcCoords    = vector4(1181.23, -3113.83, 5.03, 90.70),
    NpcModel     = 's_m_m_dockwork_01',
    HandlerSpawn = vector4(1130.10, -3083.45, 6.00, 269.29),

    -- Pagamento (range) e XP por entrega
    -- GP-H02: rebalanceado para ficar proporcional ao job regular (maxPayment=8000).
    -- Container Handler é um minijob de ~3-4 min — teto de 3500 é justo mas não sobrepõe
    -- jobs de trailer longo que com distância e carga atingem 5000-8000.
    Payment       = { min = 1200, max = 3500 },
    XPPerDelivery = 120,

    -- Raio máximo (metros) para validar entrega server-side
    MaxDeliveryRadius = 12.0,

    -- Blip permanente no mapa
    Blip = {
        sprite = 473,
        color  = 65,
        scale  = 0.4,
        label  = 'Transporte de Contêineres',
    },

    -- Blips temporários durante a missão
    BlipPickup   = { id = 537, color = 6 },
    BlipDelivery = { id = 538, color = 6 },

    -- Strings de UI (traduzíveis)
    PromptAttach    = 'Pressione ~INPUT_DETONATE~ para ~y~acoplar~s~ o contêiner',
    PromptDetach    = 'Pressione ~INPUT_DETONATE~ para ~r~soltar~s~ o contêiner',
    BlockedSpawnMsg = 'Algo está bloqueando a saída do Handler',
    DroppedMsg      = 'Contêiner caiu! Missão cancelada.',
    LostMsg         = 'Contêiner perdido! Missão cancelada.',

    -- Caminhão NPC que aparece no slot para receber o contêiner
    ExitTruck = {
        cab     = 'hauler',
        trailer = 'trflat',
        driver  = 's_m_m_dockwork_01',
    },

    -- 14 locais de pickup (Buccaneer Way — coords originais do oConteneur)
    ContainerLocations = {
        { name = 'Cais Buccaneer A', x = 1275.52, y = -3241.56, z = 4.90, h = 181.96 },
        { name = 'Cais Buccaneer B', x = 1247.42, y = -3118.35, z = 7.71, h = 91.23  },
        { name = 'Cais Buccaneer C', x = 1181.78, y = -2997.12, z = 7.71, h = 356.49 },
        { name = 'Pátio Norte A',    x = 959.22,  y = -3101.98, z = 7.71, h = 1.65   },
        { name = 'Pátio Norte B',    x = 1056.17, y = -3045.11, z = 7.71, h = 0.49   },
        { name = 'Pátio Norte C',    x = 1055.81, y = -3048.53, z = 4.90, h = 176.56 },
        { name = 'Terminal Leste A', x = 849.01,  y = -2994.32, z = 4.90, h = 359.75 },
        { name = 'Terminal Leste B', x = 903.52,  y = -3019.88, z = 7.71, h = 180.39 },
        { name = 'Terminal Leste C', x = 855.11,  y = -3074.44, z = 7.68, h = 176.41 },
        { name = 'Doca Sul A',       x = 1005.96, y = -3240.08, z = 7.71, h = 182.55 },
        { name = 'Doca Sul B',       x = 835.22,  y = -2924.18, z = 7.71, h = 178.84 },
        { name = 'Doca Sul C',       x = 872.74,  y = -3018.40, z = 4.90, h = 182.27 },
        { name = 'Entrada Porto A',  x = 1178.15, y = -3115.13, z = 5.02, h = 266.05 },
        { name = 'Entrada Porto B',  x = 1178.24, y = -3123.14, z = 7.84, h = 272.97 },
    },

    -- 11 slots de entrega com nomenclatura de pátio portuário
    DeliverySlots = {
        { name = 'Slot M-16', x = 953.23,  y = -3185.85, z = 4.90, h = 354.98 },
        { name = 'Slot M-04', x = 904.74,  y = -3186.00, z = 4.89, h = 0.03   },
        { name = 'Slot I-05', x = 909.05,  y = -3130.02, z = 4.90, h = 356.26 },
        { name = 'Slot P-16', x = 1050.25, y = -3208.71, z = 4.89, h = 178.48 },
        { name = 'Slot P-04', x = 1001.49, y = -3209.03, z = 4.90, h = 174.97 },
        { name = 'Slot O-10', x = 929.13,  y = -3210.21, z = 4.90, h = 176.28 },
        { name = 'Slot N-09', x = 1021.75, y = -3183.30, z = 4.90, h = 358.93 },
        { name = 'Slot N-18', x = 1058.59, y = -3184.71, z = 4.90, h = 357.88 },
        { name = 'Slot I-17', x = 957.07,  y = -3131.68, z = 4.90, h = 354.73 },
        { name = 'Slot K-16', x = 953.79,  y = -3153.90, z = 4.90, h = 177.37 },
        { name = 'Slot K-04', x = 904.29,  y = -3154.36, z = 4.90, h = 175.84 },
    },
}