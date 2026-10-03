fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'AURP Development Team'
description 'AUST_trucker — Sistema de Caminhoneiros — Empresas, Jobs e Economia Dinâmica'
version '20.8.0'

dependencies {
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'ox_target',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/logistics_config.lua',
    'shared/config.lua',
    'lang/br.lua',
    'lang/en.lua',
    'lang/locale.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',     -- Framework abstraction (QBX/QBCore/ESX)
    'server/database.lua',      -- Schema (SchemaService) + todos os helpers de DB
    'server/main.lua',
    'server/services/company_service.lua',
    'server/services/party_service.lua',
    'server/services/loan_service.lua',
    'server/services/truck_fleet_service.lua',
    'server/services/repo_service.lua',    -- após loan_service (usa LoanService via CheckOverdue)
    'server/flatbed.server.lua',
    'server/services/economy_service.lua',
    'server/services/industry_ownership_service.lua',  -- Fase 2: após economy, antes de industry
    'server/services/industry_service.lua',
    'server/services/progression_service.lua',
    'server/services/adr_service.lua',
    'server/services/forklift_service.lua',
    'server/services/cargo_tracking_service.lua',   -- v14: após forklift, antes de job_service
    'server/services/anti_cheat_service.lua',        -- v15: após cargo_tracking, antes de job_service
    'server/services/container_handler_service.lua', -- v20: Handler portuário (integração oConteneur)
    'server/services/job_service.lua',
    'server/services/convoy_service.lua',
    'server/services/illegal_service.lua',
    'server/services/contract_service.lua',      -- Contratos de frete (entregas empresa)
    'server/services/shop_stock_service.lua',   -- v16: Ecossistema estoque lojas (após contract_service)
    'server/services/npc_driver_service.lua',   -- Fase 4A: após illegal_service
    'server/services/truck_simulation_service.lua',
    'server/crude_oil.lua',
    'server/services/parcel_service.lua',  -- v19/v20: Parcel Delivery (antes de exports — ParcelService global)
    'server/services/truck_rental_service.lua', -- Sistema de Aluguel e Caução de Caminhões
    'server/services/admin_service.lua',       -- Painel Administrativo e Gestão de Rotas Dinâmicas
    'server/exports.lua',
    'server/exports_shop.lua',   -- v16: exports estoque lojas
    'server/adr_questions.lua',   -- banco de perguntas ADR (gabarito só no servidor)
    'server/callbacks.lua',
    'server/events.lua',
}

client_scripts {
    'client/modules/forklift.lua',
    'client/modules/reach_stacker.lua',
    'client/modules/adr_hazard.lua',
    'client/modules/car_carrier.lua',
    'client/modules/dataview.lua',
    'client/modules/offset_editor.lua',        -- Módulo de Calibração Visual 3D e Gestão de Spawns
    'client/zones.lua',
    'client/cargo_dry.lua',
    'client/cargo_liquid.lua',
    'client/main.lua',
    'client/carry_system.lua',             -- v19: CarrySystem (antes de todos)
    'client/client.lua',
    'client/hud.client.lua',
    'client/adr.client.lua',
    'client/forklift.client.lua',
    'client/cargo_theft.client.lua',    -- v14: cargo theft mechanics
    'client/convoy.client.lua',
    'client/illegal.client.lua',
    'client/flatbed.client.lua',
    'client/repo.client.lua',
    'client/npc_driver.client.lua',
    'client/industries.client.lua',
    'client/industries_npc.client.lua',
    'client/crude_oil.lua',
    'client/parcel_delivery.lua',          -- v19: Parcel Delivery
    'client/container_handler.client.lua', -- v20: Handler portuário (integração oConteneur)
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/panel.js',
    'html/css/*',
    'html/js/*',
    'html/vendor/**',
    'html/lang/*',
    'html/img/*',
    'html/img/avatar/*',
    'html/img/icons/*',
    'html/img/trailers/*',
    'html/img/trucks/*',
    'html/assets/*',
    'data/*.meta',
}

data_file 'HANDLING_FILE' 'data/aerocab_handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/aerocab_vehicles.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/aerocab_carvariations.meta'

data_file 'HANDLING_FILE' 'data/brickades_handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/brickades_vehicles.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/brickades_carvariations.meta'
data_file 'DLC_TEXT_FILE' 'data/brickades_dlctext.meta'

data_file 'HANDLING_FILE' 'data/linerunner_handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/linerunner_vehicles.meta'
data_file 'DLC_TEXT_FILE' 'data/linerunner_dlctext.meta'

data_file 'HANDLING_FILE' 'data/vetirs_handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/vetirs_vehicles.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/vetirs_carvariations.meta'
data_file 'DLC_TEXT_FILE' 'data/vetirs_dlctext.meta'

data_file 'DLC_ITYP_REQUEST' 'stream/sm3d_prop_logi_shelf_def.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/sm3d_prop_pallets_def.ytyp'
