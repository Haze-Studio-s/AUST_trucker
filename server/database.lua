-- aurp_trucker — server/database.lua
-- FONTE CANÔNICA do banco de dados: schema (tabelas + migrations) + helpers de query.
--
-- Para adicionar uma nova tabela:
--   1. Adicione o CREATE TABLE IF NOT EXISTS no array TABLES abaixo.
--   2. Para servidores existentes, adicione um ALTER TABLE no array MIGRATIONS.
--   3. Atualize import.sql se quiser manter o arquivo de referência manual em sincronia.
--
-- NÃO editar server/schema.lua — ele é apenas um stub de compatibilidade.

-- ============================================================
-- SCHEMA SERVICE — auto-cria tabelas no primeiro boot
-- ============================================================

SchemaService = {}

local TABLES = {
    [[CREATE TABLE IF NOT EXISTS `trucker_companies` (
        `id`                VARCHAR(50)  PRIMARY KEY,
        `owner_citizenid`   VARCHAR(50)  NOT NULL,
        `name`              VARCHAR(100) NOT NULL UNIQUE,
        `balance`           BIGINT       DEFAULT 0,
        `is_recruiting`     TINYINT(1)   DEFAULT 0,
        `company_type`      ENUM('logistics','repo') DEFAULT 'logistics',
        `company_level`     TINYINT      DEFAULT 1,
        `company_xp`        INT          DEFAULT 0,
        `reputation`        TINYINT(3) UNSIGNED NOT NULL DEFAULT 100,
        `allow_illegal_npc` TINYINT(1)   NOT NULL DEFAULT 0,
        `created_at`        DATETIME     DEFAULT CURRENT_TIMESTAMP,
        `fleet_upgrades`    JSON         DEFAULT ('{}')
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_company_members` (
        `citizenid`  VARCHAR(50) PRIMARY KEY,
        `company_id` VARCHAR(50) NOT NULL,
        `role`       ENUM('owner','manager','driver') DEFAULT 'driver',
        `joined_at`  DATETIME    DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (`company_id`) REFERENCES `trucker_companies`(`id`) ON DELETE CASCADE,
        INDEX `idx_company_id` (`company_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_company_vehicles` (
        `plate`           VARCHAR(20) PRIMARY KEY,
        `company_id`      VARCHAR(50) NOT NULL,
        `model`           VARCHAR(50) NOT NULL,
        `vehicle_type`    VARCHAR(50) NOT NULL,
        `status`          ENUM('stored','out') DEFAULT 'stored',
        `added_at`        DATETIME    DEFAULT CURRENT_TIMESTAMP,
        `fuel_level`      FLOAT       DEFAULT 100.0,
        `has_gps_tracker` TINYINT(1)  NOT NULL DEFAULT 0,
        FOREIGN KEY (`company_id`) REFERENCES `trucker_companies`(`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_jobs` (
        `id`                 VARCHAR(50)   PRIMARY KEY,
        `origin_id`          VARCHAR(50)   NOT NULL,
        `dest_id`            VARCHAR(50)   NOT NULL,
        `cargo_item`         VARCHAR(100)  NOT NULL,
        `trailer_model`      VARCHAR(50)   NOT NULL,
        `base_payment`       INT           NOT NULL,
        `distance`           DECIMAL(10,2) NOT NULL,
        `status`             ENUM('available','active','completed','expired','npc_completed') DEFAULT 'available',
        `assigned_citizenid` VARCHAR(50)   NULL,
        `company_id`         VARCHAR(50)   NULL,
        `convoy_id`          VARCHAR(36)   NULL DEFAULT NULL,
        `illegal_type`       VARCHAR(20)   NULL DEFAULT NULL,
        `cargo_qty`          TINYINT UNSIGNED NOT NULL DEFAULT 1,
        `truck_plate`        VARCHAR(20)   DEFAULT NULL,
        `weight`             INT           NOT NULL DEFAULT 80,
        `expires_at`         DATETIME      NOT NULL,
        `accepted_at`        DATETIME      NULL,
        `completed_at`       DATETIME      NULL,
        `created_at`         DATETIME      DEFAULT CURRENT_TIMESTAMP,
        INDEX `idx_status`         (`status`),
        INDEX `idx_assigned`       (`assigned_citizenid`),
        INDEX `idx_status_expires` (`status`, `expires_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_industry_state` (
        `industry_id`          VARCHAR(50) NOT NULL,
        `item`                 VARCHAR(50) NOT NULL,
        `entry_type`           ENUM('production','consumption') NOT NULL,
        `current_price`        INT         NOT NULL,
        `current_stock`        INT         DEFAULT 0,
        `next_production_time` DATETIME    NULL,
        `last_npc_fill_at`     DATETIME    NULL DEFAULT NULL,
        `updated_at`           DATETIME    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`industry_id`, `item`, `entry_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_industry_ownership` (
        `industry_id`      VARCHAR(50) PRIMARY KEY,
        `owner_citizenid`  VARCHAR(50) NOT NULL,
        `company_id`       VARCHAR(50) NULL,
        `purchase_price`   BIGINT      NOT NULL,
        `production_level` TINYINT     DEFAULT 1,
        `npc_workers`      TINYINT     DEFAULT 0,
        `balance`          BIGINT      DEFAULT 0,
        `total_earned`     BIGINT      DEFAULT 0,
        `purchased_at`     DATETIME    DEFAULT CURRENT_TIMESTAMP,
        `updated_at`       DATETIME    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX `idx_owner`      (`owner_citizenid`),
        INDEX `idx_company_id` (`company_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_player_progression` (
        `citizenid`        VARCHAR(50)   PRIMARY KEY,
        `level`            INT           DEFAULT 1,
        `xp`               INT           DEFAULT 0,
        `rank`             TINYINT       DEFAULT 1,
        `reputation`       INT           DEFAULT 0,
        `skill_points`     INT           DEFAULT 0,
        `total_earnings`   BIGINT        DEFAULT 0,
        `total_deliveries` INT           DEFAULT 0,
        `total_distance`   DECIMAL(12,2) DEFAULT 0,
        `joined_at`        DATETIME      DEFAULT CURRENT_TIMESTAMP,
        `last_seen`        DATETIME      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        `fatigue`          FLOAT         DEFAULT 0.0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_player_skills` (
        `citizenid`   VARCHAR(50) NOT NULL,
        `skill_type`  ENUM('distance','valuable','fragile','speed') NOT NULL,
        `skill_level` TINYINT     DEFAULT 0,
        PRIMARY KEY (`citizenid`, `skill_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_loans` (
        `id`                INT          AUTO_INCREMENT PRIMARY KEY,
        `citizenid`         VARCHAR(50)  NOT NULL,
        `company_id`        VARCHAR(50)  NULL,
        `vehicle_plate`     VARCHAR(20)  NULL,
        `amount`            BIGINT       NOT NULL,
        `interest_rate`     FLOAT        NOT NULL DEFAULT 0.05,
        `remaining_balance` BIGINT       NOT NULL,
        `monthly_payment`   BIGINT       NOT NULL,
        `status`            ENUM('active','paid','defaulted') DEFAULT 'active',
        `created_at`        DATETIME     DEFAULT CURRENT_TIMESTAMP,
        `next_payment_at`   DATETIME     NOT NULL,
        INDEX `idx_citizenid` (`citizenid`),
        INDEX `idx_status`    (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_npc_drivers` (
        `id`               VARCHAR(36) NOT NULL PRIMARY KEY,
        `company_id`       VARCHAR(50) NOT NULL,
        `name`             VARCHAR(64) NOT NULL,
        `skill_level`      ENUM('junior','pleno','senior') NOT NULL DEFAULT 'junior',
        `salary`           INT         NOT NULL DEFAULT 2000,
        `satisfaction`     TINYINT     NOT NULL DEFAULT 80,
        `xp`               INT         NOT NULL DEFAULT 0,
        `tenure_days`      INT         NOT NULL DEFAULT 0,
        `total_earnings`   INT         NOT NULL DEFAULT 0,
        `status`           ENUM('idle','working','resting','fired','quit') NOT NULL DEFAULT 'idle',
        `active_job_id`    VARCHAR(36) NULL DEFAULT NULL,
        `hired_at`         TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `last_demand_at`   INT         NULL DEFAULT NULL,
        `last_tenure_check` INT        NULL DEFAULT NULL,
        `resting_until`    INT         NULL DEFAULT NULL,
        FOREIGN KEY (`company_id`) REFERENCES `trucker_companies`(`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_npc_jobs` (
        `id`              VARCHAR(36) NOT NULL PRIMARY KEY,
        `driver_id`       VARCHAR(36) NOT NULL,
        `company_id`      VARCHAR(50) NOT NULL,
        `origin_id`       VARCHAR(64) NOT NULL,
        `dest_id`         VARCHAR(64) NOT NULL,
        `cargo_item`      VARCHAR(64) NOT NULL,
        `base_payment`    INT         NOT NULL DEFAULT 0,
        `distance`        FLOAT       NOT NULL DEFAULT 0,
        `illegal`         TINYINT(1)  NOT NULL DEFAULT 0,
        `assigned_at`     INT         NOT NULL,
        `expected_end_at` INT         NOT NULL,
        `status`          ENUM('active','completed','failed','event') NOT NULL DEFAULT 'active',
        `earnings`        INT         NOT NULL DEFAULT 0,
        FOREIGN KEY (`driver_id`) REFERENCES `trucker_npc_drivers`(`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_repo_orders` (
        `id`                      INT          AUTO_INCREMENT PRIMARY KEY,
        `company_id`              VARCHAR(50)  NULL,
        `vehicle_plate`           VARCHAR(20)  NOT NULL,
        `vehicle_owner_citizenid` VARCHAR(50)  NULL,
        `vehicle_model`           VARCHAR(50)  NOT NULL,
        `vehicle_value`           BIGINT       NOT NULL,
        `mission_type`            ENUM('simple','npc_hostile','pvp','stealth') DEFAULT 'simple',
        `location_zone`           VARCHAR(50)  NOT NULL,
        `status`                  ENUM('available','active','completed','failed','expired') DEFAULT 'available',
        `assigned_citizenid`      VARCHAR(50)  NULL,
        `payment`                 BIGINT       NOT NULL,
        `loan_id`                 INT          NULL,
        `created_at`              DATETIME     DEFAULT CURRENT_TIMESTAMP,
        `expires_at`              DATETIME     NOT NULL,
        `completed_at`            DATETIME     NULL,
        INDEX `idx_status`            (`status`),
        INDEX `idx_vehicle_owner`     (`vehicle_owner_citizenid`),
        INDEX `idx_status_expires`    (`status`, `expires_at`),
        INDEX `idx_company_id`        (`company_id`),
        UNIQUE KEY `uq_loan_id`       (`loan_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_infractions` (
        `id`              INT          AUTO_INCREMENT PRIMARY KEY,
        `citizenid`       VARCHAR(50)  NOT NULL,
        `job_id`          VARCHAR(50)  NULL,
        `infraction_type` ENUM('overload','no_manifest','expired_manifest',
                              'dangerous_cargo','illegal_seizure') NOT NULL,
        `reason`          TEXT         NOT NULL,
        `issued_by`       VARCHAR(100) NOT NULL,
        `created_at`      DATETIME     DEFAULT CURRENT_TIMESTAMP,
        INDEX `idx_citizenid` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_parties` (
        `id`         VARCHAR(36) PRIMARY KEY,
        `leader_cid` VARCHAR(50) NOT NULL,
        `members`    JSON        NOT NULL DEFAULT '[]',
        `max_size`   INT         NOT NULL DEFAULT 6,
        `status`     ENUM('forming','active','disbanded') NOT NULL DEFAULT 'forming',
        `created_at` DATETIME    NOT NULL DEFAULT NOW()
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_convoy_jobs` (
        `id`           VARCHAR(36) PRIMARY KEY,
        `party_id`     VARCHAR(36) NOT NULL,
        `status`       ENUM('forming','active','completed','cancelled') NOT NULL DEFAULT 'forming',
        `bonus_mult`   FLOAT       NOT NULL DEFAULT 1.5,
        `active_count` INT         NOT NULL DEFAULT 0,
        `total_count`  INT         NOT NULL DEFAULT 0,
        `started_at`   DATETIME    NULL,
        `completed_at` DATETIME    NULL,
        FOREIGN KEY (`party_id`) REFERENCES `trucker_parties`(`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_convoy_members` (
        `convoy_id` VARCHAR(36) NOT NULL,
        `citizenid` VARCHAR(50) NOT NULL,
        `job_id`    VARCHAR(50) NOT NULL,
        `status`    ENUM('pending','active','completed','abandoned') NOT NULL DEFAULT 'pending',
        PRIMARY KEY (`convoy_id`, `citizenid`),
        FOREIGN KEY (`convoy_id`) REFERENCES `trucker_convoy_jobs`(`id`),
        FOREIGN KEY (`job_id`)    REFERENCES `trucker_jobs`(`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Histórico de pagamentos por membro (um registro por membro que completou o convoy)
    [[CREATE TABLE IF NOT EXISTS `trucker_convoy_payments` (
        `id`              INT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
        `convoy_id`       VARCHAR(36)   NOT NULL,
        `citizenid`       VARCHAR(50)   NOT NULL,
        `amount`          INT           NOT NULL DEFAULT 0,
        `bonus_mult`      FLOAT         NOT NULL DEFAULT 1.0,
        `completed_count` TINYINT       NOT NULL DEFAULT 1,
        `total_count`     TINYINT       NOT NULL DEFAULT 1,
        `created_at`      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (`convoy_id`) REFERENCES `trucker_convoy_jobs`(`id`) ON DELETE CASCADE,
        INDEX `idx_cp_citizenid` (`citizenid`),
        INDEX `idx_cp_created`   (`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Pagamentos pendentes (jogador offline / falha no crédito): pagos por ContractService.PayPending
    [[CREATE TABLE IF NOT EXISTS `trucker_pending_payouts` (
        `id`         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        `citizenid`  VARCHAR(50)  NOT NULL,
        `amount`     INT          NOT NULL DEFAULT 0,
        `reason`     VARCHAR(100) NOT NULL DEFAULT '',
        `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX `idx_pp_citizen` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_adr_certs` (
        `id`         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        `citizenid`  VARCHAR(50) NOT NULL,
        `adr_type`   ENUM('flammable_liquid','flammable_gas','toxic','corrosive',
                         'explosive','environmental') NOT NULL,
        `expires_at` INT UNSIGNED NOT NULL,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY `uq_citizen_type` (`citizenid`, `adr_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Contratos de frete (entregas de empresa)
    [[CREATE TABLE IF NOT EXISTS `trucker_contracts` (
        `id`                  VARCHAR(50)  PRIMARY KEY,
        `contract_type`       ENUM('simple','multi') NOT NULL DEFAULT 'simple',
        `total_payment`       INT          NOT NULL DEFAULT 0,
        `status`              ENUM('available','active','completed','expired') DEFAULT 'available',
        `assigned_citizenid`  VARCHAR(50)  NULL,
        `company_id`          VARCHAR(50)  NULL,
        `created_at`          DATETIME     DEFAULT CURRENT_TIMESTAMP,
        `accepted_at`         DATETIME     NULL,
        `completed_at`        DATETIME     NULL,
        `expires_at`          DATETIME     NOT NULL,
        INDEX `idx_contract_status` (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_contract_stops` (
        `id`             INT AUTO_INCREMENT PRIMARY KEY,
        `contract_id`    VARCHAR(50) NOT NULL,
        `stop_order`     TINYINT     NOT NULL,
        `location_id`    VARCHAR(50) NOT NULL,
        `location_name`  VARCHAR(100) NOT NULL,
        `coords_x`       FLOAT NOT NULL,
        `coords_y`       FLOAT NOT NULL,
        `coords_z`       FLOAT NOT NULL,
        `action`         ENUM('pickup','delivery') NOT NULL DEFAULT 'pickup',
        `cargo_item`     VARCHAR(100) NOT NULL,
        `cargo_qty`      INT NOT NULL DEFAULT 1,
        `completed`      TINYINT(1) NOT NULL DEFAULT 0,
        FOREIGN KEY (`contract_id`) REFERENCES `trucker_contracts`(`id`) ON DELETE CASCADE,
        INDEX `idx_stop_contract` (`contract_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `trucker_client_relationships` (
        `id`               INT          AUTO_INCREMENT PRIMARY KEY,
        `company_id`       VARCHAR(50)  NOT NULL,
        `client_id`        VARCHAR(50)  NOT NULL,
        `trust_level`      TINYINT      NOT NULL DEFAULT 1,
        `trust_xp`         INT          NOT NULL DEFAULT 0,
        `total_deliveries` INT          NOT NULL DEFAULT 0,
        `total_revenue`    BIGINT       NOT NULL DEFAULT 0,
        `streak`           INT          NOT NULL DEFAULT 0,
        `last_delivery_at` DATETIME     NULL,
        `created_at`       DATETIME     DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY `uq_company_client` (`company_id`, `client_id`),
        INDEX `idx_rel_company` (`company_id`),
        INDEX `idx_rel_client`  (`client_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Shop Stock Ecosystem (v16.0.0)
    [[CREATE TABLE IF NOT EXISTS `trucker_shop_stock` (
        `shop_id`              VARCHAR(80)  NOT NULL,
        `item_name`            VARCHAR(50)  NOT NULL,
        `current_stock`        INT          NOT NULL DEFAULT 100,
        `max_stock`            INT          NOT NULL DEFAULT 200,
        `min_threshold`        INT          NOT NULL DEFAULT 20,
        `reorder_qty`          INT          NOT NULL DEFAULT 50,
        `price_per_unit`       INT          NOT NULL DEFAULT 15,
        `linked_industry_type` VARCHAR(50)  DEFAULT 'food',
        `management_type`      ENUM('npc','player') NOT NULL DEFAULT 'npc',
        `owner_citizenid`      VARCHAR(50)  NULL,
        `pending_contract_id`  VARCHAR(50)  NULL,
        `last_restock_at`      DATETIME     NULL,
        `updated_at`           DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`shop_id`, `item_name`),
        INDEX `idx_low_stock` (`current_stock`, `min_threshold`),
        INDEX `idx_pending` (`pending_contract_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Truck Rental & Caution Deposit (v20.2.0)
    [[CREATE TABLE IF NOT EXISTS `trucker_rentals` (
        `citizenid`   VARCHAR(50) PRIMARY KEY,
        `plate`       VARCHAR(20) NOT NULL,
        `model`       VARCHAR(50) NOT NULL,
        `deposit`     INT         NOT NULL,
        `fee`         INT         NOT NULL,
        `refund_due`  INT         NULL DEFAULT NULL, -- estorno pendente (desconexão/restart)
        `rented_at`   DATETIME    DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- lc_truck_logistics: Frota de Caminhões Próprios e Condição Mecânica
    [[CREATE TABLE IF NOT EXISTS `trucker_trucks` (
        `truck_id`     INT(10) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `user_id`      VARCHAR(50) NOT NULL,
        `truck_name`   VARCHAR(50) NOT NULL,
        `driver`       INT(10) UNSIGNED NULL DEFAULT NULL,
        `body`         SMALLINT(5) UNSIGNED NOT NULL DEFAULT 1000,
        `engine`       SMALLINT(5) UNSIGNED NOT NULL DEFAULT 1000,
        `transmission` SMALLINT(5) UNSIGNED NOT NULL DEFAULT 1000,
        `wheels`       SMALLINT(5) UNSIGNED NOT NULL DEFAULT 1000,
        `fuel`         INT(11) UNSIGNED NOT NULL DEFAULT 100,
        `properties`   LONGTEXT NOT NULL,
        `garage_id`    VARCHAR(50) NOT NULL DEFAULT 'trucker_1',
        INDEX `idx_tt_user` (`user_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- lc_truck_logistics: Reboques Próprios
    [[CREATE TABLE IF NOT EXISTS `trucker_trailers` (
        `trailer_id`   INT(10) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `user_id`      VARCHAR(50) NOT NULL,
        `trailer_name` VARCHAR(50) NOT NULL,
        `body`         SMALLINT(5) UNSIGNED NOT NULL DEFAULT 1000,
        `garage_id`    VARCHAR(50) NOT NULL DEFAULT 'trucker_1',
        `properties`   LONGTEXT NULL DEFAULT NULL,
        INDEX `idx_tr_user` (`user_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- lc_truck_logistics: Sedes e Garagens Adquiridas
    [[CREATE TABLE IF NOT EXISTS `trucker_garages` (
        `id`           INT(10) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `user_id`      VARCHAR(50) NOT NULL,
        `garage_id`    VARCHAR(50) NOT NULL,
        `level`        TINYINT(3) UNSIGNED NOT NULL DEFAULT 1,
        `max_slots`    TINYINT(3) UNSIGNED NOT NULL DEFAULT 2,
        `purchased_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY `uq_user_garage` (`user_id`, `garage_id`),
        INDEX `idx_tg_user` (`user_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- lc_truck_logistics: Motoristas NPCs Contratados
    [[CREATE TABLE IF NOT EXISTS `trucker_drivers` (
        `driver_id`    INT(10) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `user_id`      VARCHAR(50) NULL DEFAULT NULL,
        `name`         VARCHAR(50) NOT NULL DEFAULT '',
        `product_type` TINYINT(3) UNSIGNED NOT NULL DEFAULT 0,
        `distance`     TINYINT(3) UNSIGNED NOT NULL DEFAULT 0,
        `valuable`     TINYINT(3) UNSIGNED NOT NULL DEFAULT 0,
        `fragile`      TINYINT(3) UNSIGNED NOT NULL DEFAULT 0,
        `fast`         TINYINT(3) UNSIGNED NOT NULL DEFAULT 0,
        `price`        INT(10) UNSIGNED NOT NULL DEFAULT 0,
        `img`          VARCHAR(50) NULL DEFAULT NULL,
        `truck_id`     INT(10) UNSIGNED NULL DEFAULT NULL,
        INDEX `idx_td_user` (`user_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Logística 2.0: aust_trucker_stats para progressão persistente e recompensas
    [[CREATE TABLE IF NOT EXISTS `aust_trucker_stats` (
        `citizenid` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_unicode_ci',
        `level` INT(11) NOT NULL DEFAULT 1,
        `exp` INT(11) NOT NULL DEFAULT 0,
        `deliveries` INT(11) NOT NULL DEFAULT 0,
        PRIMARY KEY (`citizenid`) USING BTREE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    -- Módulo Administrativo: Rotas e Contratos Dinâmicos
    [[CREATE TABLE IF NOT EXISTS `aust_trucker_custom_routes` (
        `id` VARCHAR(50) PRIMARY KEY,
        `name` VARCHAR(100) NOT NULL,
        `type` ENUM('quick', 'freight', 'adr', 'heavy', 'carrier') NOT NULL DEFAULT 'quick',
        `cargo_model` VARCHAR(100) NOT NULL DEFAULT 'hei_prop_carrier_cargo_04b',
        `cargo_name` VARCHAR(100) NOT NULL DEFAULT 'Carga Padrão',
        `truck_model` VARCHAR(50) NOT NULL DEFAULT 'hauler',
        `trailer_model` VARCHAR(50) NOT NULL DEFAULT 'trailers2',
        `base_payment` INT NOT NULL DEFAULT 5000,
        `base_xp` INT NOT NULL DEFAULT 200,
        `req_skill` INT NOT NULL DEFAULT 0,
        `fragile` TINYINT(1) NOT NULL DEFAULT 0,
        `valuable` TINYINT(1) NOT NULL DEFAULT 0,
        `pickup_coords` JSON NOT NULL,
        `delivery_coords` JSON NOT NULL,
        `is_active` TINYINT(1) NOT NULL DEFAULT 1,
        `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
        `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Módulo Administrativo: Spawns e Baías Dinâmicas
    [[CREATE TABLE IF NOT EXISTS `aust_trucker_spawns` (
        `id` VARCHAR(50) PRIMARY KEY,
        `name` VARCHAR(100) NOT NULL,
        `spawn_type` ENUM('truck', 'trailer', 'forklift', 'pallet', 'handler', 'loading_bay', 'delivery', 'load_bay', 'delivery_bay') NOT NULL,
        `folder_name` VARCHAR(100) NOT NULL DEFAULT 'Geral',
        `coords` JSON NOT NULL,
        `heading` FLOAT NOT NULL DEFAULT 0.0,
        `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Módulo Administrativo: Offsets de Slots de Trailer Mapeados Visualmente
    [[CREATE TABLE IF NOT EXISTS `aust_trucker_trailer_offsets` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `trailer_model` VARCHAR(50) NOT NULL,
        `label` VARCHAR(100) DEFAULT NULL,
        `prop_model` VARCHAR(100) DEFAULT NULL,
        `slot_index` INT NOT NULL,
        `offset_x` FLOAT NOT NULL DEFAULT 0.0,
        `offset_y` FLOAT NOT NULL DEFAULT 0.0,
        `offset_z` FLOAT NOT NULL DEFAULT 0.0,
        `heading` FLOAT NOT NULL DEFAULT 0.0,
        `is_forklift` TINYINT(1) NOT NULL DEFAULT 0,
        `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY `uq_trailer_slot` (`trailer_model`, `slot_index`, `is_forklift`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Módulo Administrativo: Props de Cargas Homologados
    [[CREATE TABLE IF NOT EXISTS `aust_trucker_homologated_props` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `model_hash` VARCHAR(100) NOT NULL UNIQUE,
        `name` VARCHAR(100) NOT NULL,
        `cargo_category` ENUM('dry', 'fragile', 'valuable', 'adr', 'heavy') NOT NULL DEFAULT 'dry',
        `offset_x` FLOAT NOT NULL DEFAULT 0.0,
        `offset_y` FLOAT NOT NULL DEFAULT 0.0,
        `offset_z` FLOAT NOT NULL DEFAULT 0.0,
        `heading` FLOAT NOT NULL DEFAULT 0.0,
        `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Módulo Administrativo: NPCs Despachantes Dinâmicos
    [[CREATE TABLE IF NOT EXISTS `aust_trucker_npcs` (
        `id` VARCHAR(50) PRIMARY KEY,
        `name` VARCHAR(100) NOT NULL,
        `model` VARCHAR(50) NOT NULL DEFAULT 's_m_m_dockwork_01',
        `coords` JSON NOT NULL,
        `heading` FLOAT NOT NULL DEFAULT 0.0,
        `blip_sprite` INT NOT NULL DEFAULT 477,
        `blip_color` INT NOT NULL DEFAULT 2,
        `is_active` TINYINT(1) NOT NULL DEFAULT 1,
        `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- Módulo Administrativo: Configurações de Economia e Multiplicadores
    [[CREATE TABLE IF NOT EXISTS `aust_trucker_economy_settings` (
        `key_name` VARCHAR(50) PRIMARY KEY,
        `numeric_value` FLOAT NOT NULL,
        `description` VARCHAR(255) NULL,
        `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- Migrations para servidores existentes (pcall ignora se coluna já existe)
local MIGRATIONS = {
    "ALTER TABLE trucker_rentals ADD COLUMN refund_due INT NULL DEFAULT NULL", -- aluguel: estorno pendente
    "ALTER TABLE trucker_jobs ADD COLUMN weight INT NOT NULL DEFAULT 80",
    "ALTER TABLE trucker_contracts ADD COLUMN client_id VARCHAR(50)",
    "ALTER TABLE trucker_contracts ADD COLUMN relationship_id INT",
    "ALTER TABLE trucker_contracts ADD COLUMN bonus_percent INT DEFAULT 0",
    "ALTER TABLE trucker_contracts ADD COLUMN negotiated_payment INT DEFAULT 0",
    -- v16.0.0: Shop Stock Ecosystem
    "ALTER TABLE trucker_contracts ADD COLUMN contract_source ENUM('negotiation','resupply','auto') DEFAULT 'negotiation'",
    "ALTER TABLE trucker_contracts ADD COLUMN target_shop_id VARCHAR(80) NULL",
    "ALTER TABLE trucker_contracts ADD COLUMN target_item VARCHAR(50) NULL",
    -- lc_truck_logistics compatibility: trucker_jobs
    "ALTER TABLE `trucker_jobs` ADD COLUMN `contract_type` TINYINT NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_jobs` ADD COLUMN `cargo_type` TINYINT NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_jobs` ADD COLUMN `fragile` TINYINT NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_jobs` ADD COLUMN `valuable` TINYINT NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_jobs` ADD COLUMN `fast` TINYINT NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_jobs` ADD COLUMN `illegal` TINYINT NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_jobs` ADD COLUMN `external_data` TEXT NULL DEFAULT NULL",
    -- lc_truck_logistics compatibility: trucker_loans
    "ALTER TABLE `trucker_loans` ADD COLUMN `loan` INT UNSIGNED NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_loans` ADD COLUMN `remaining_amount` INT UNSIGNED NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_loans` ADD COLUMN `day_cost` INT UNSIGNED NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_loans` ADD COLUMN `taxes_on_day` INT UNSIGNED NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_loans` ADD COLUMN `timer` INT UNSIGNED NOT NULL DEFAULT 0",
    -- lc_truck_logistics compatibility: skills expansion
    "ALTER TABLE `trucker_player_skills` MODIFY COLUMN `skill_type` VARCHAR(32) NOT NULL",
    "ALTER TABLE `trucker_player_progression` ADD COLUMN `product_type` TINYINT UNSIGNED NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_player_progression` ADD COLUMN `distance_skill` TINYINT UNSIGNED NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_player_progression` ADD COLUMN `valuable_skill` TINYINT UNSIGNED NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_player_progression` ADD COLUMN `fragile_skill` TINYINT UNSIGNED NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_player_progression` ADD COLUMN `fast_skill` TINYINT UNSIGNED NOT NULL DEFAULT 0",
    "ALTER TABLE `trucker_player_progression` ADD COLUMN `illegal_skill` TINYINT UNSIGNED NOT NULL DEFAULT 0",
    -- admin overhaul: offsets label, prop_model and spawns folder_name
    "ALTER TABLE `aust_trucker_trailer_offsets` ADD COLUMN `label` VARCHAR(100) DEFAULT NULL",
    "ALTER TABLE `aust_trucker_trailer_offsets` ADD COLUMN `prop_model` VARCHAR(100) DEFAULT NULL",
    "ALTER TABLE `aust_trucker_spawns` ADD COLUMN `folder_name` VARCHAR(100) NOT NULL DEFAULT 'Geral'",
    "ALTER TABLE `aust_trucker_spawns` MODIFY COLUMN `spawn_type` ENUM('truck', 'trailer', 'forklift', 'pallet', 'handler', 'loading_bay', 'delivery', 'load_bay', 'delivery_bay') NOT NULL",
    "ALTER TABLE `trucker_repo_orders` ADD COLUMN `accepted_at` DATETIME NULL DEFAULT NULL",
    -- calote: parcelas perdidas consecutivas (ao atingir Config.Loans.MaxMissedPayments => 'defaulted')
    "ALTER TABLE `trucker_loans` ADD COLUMN `missed_payments` TINYINT UNSIGNED NOT NULL DEFAULT 0",
    -- infraction_type: adiciona 'cargo_damage' (usado por job_service); MODIFY é idempotente
    "ALTER TABLE `trucker_infractions` MODIFY COLUMN `infraction_type` ENUM('overload','no_manifest','expired_manifest','dangerous_cargo','illegal_seizure','cargo_damage') NOT NULL",
    -- trucker_jobs.status: adiciona 'failed' (usado por DB_SetCargoFailed)
    "ALTER TABLE `trucker_jobs` MODIFY COLUMN `status` ENUM('available','active','completed','expired','npc_completed','failed') DEFAULT 'available'",
    -- índices (idempotentes: erro de chave duplicada é ignorado)
    "ALTER TABLE `trucker_loans` ADD INDEX `idx_loans_company` (`company_id`)",
    "ALTER TABLE `trucker_loans` ADD INDEX `idx_loans_status_next` (`status`, `next_payment_at`)",
    "ALTER TABLE `trucker_jobs` ADD INDEX `idx_jobs_truck_plate` (`truck_plate`)",
    "ALTER TABLE `trucker_jobs` ADD INDEX `idx_jobs_company` (`company_id`)",
    -- impede pagamento duplicado de convoy (falha e é logado se já houver duplicatas)
    "ALTER TABLE `trucker_convoy_payments` ADD UNIQUE INDEX `uq_cp_convoy_citizen` (`convoy_id`, `citizenid`)",
}

-- Erros esperados em migrations idempotentes (coluna/chave já existe)
local function IsExpectedMigrationError(err)
    local e = tostring(err or ''):lower()
    return e:find('duplicate column', 1, true)
        or e:find('duplicate key name', 1, true)
        or e:find('already exists', 1, true)
        or e:find('1060', 1, true)
        or e:find('1061', 1, true)
end

---Garante que todas as tabelas e migrations existam. Chamado dentro de MySQL.ready (main.lua).
function SchemaService.EnsureTables()
    for _, sql in ipairs(TABLES) do
        local ok, err = pcall(MySQL.query.await, sql)
        if not ok then
            print(('[aurp_trucker] SchemaService ERROR creating table: %s'):format(tostring(err)))
        end
    end
    for _, sql in ipairs(MIGRATIONS) do
        local ok, err = pcall(MySQL.query.await, sql)
        if not ok and not IsExpectedMigrationError(err) then
            print(('[aurp_trucker] SchemaService MIGRATION FAILED: %s | %s'):format(sql, tostring(err)))
        end
    end
    if Config.Debug then
        print('[aurp_trucker] SchemaService: tables ensured.')
    end
end

-- ============================================================
-- COMPANIES
-- ============================================================

function DB_CreateCompany(id, ownerCitizenId, name, companyType)
    companyType = companyType or 'logistics'
    return MySQL.insert.await(
        'INSERT INTO trucker_companies (id, owner_citizenid, name, company_type) VALUES (?, ?, ?, ?)',
        { id, ownerCitizenId, name, companyType }
    )
end

function DB_GetCompany(companyId)
    return MySQL.single.await(
        'SELECT * FROM trucker_companies WHERE id = ? LIMIT 1',
        { companyId }
    )
end

function DB_UpdateCompanyBalance(companyId, amount, allowNegative)
    -- amount pode ser negativo (saque) ou positivo (depósito)
    -- M-11: capturar affected rows — retorna nil em falha (empresa não encontrada ou DB error)
    -- Débitos são atômicos: só aplicam se balance >= valor (retorna nil caso contrário),
    -- evitando saldo negativo por chamadas concorrentes. `allowNegative` (true) mantém o
    -- comportamento antigo para multas/penalidades que podem deixar o saldo negativo.
    if type(amount) ~= 'number' or amount ~= amount or amount == math.huge or amount == -math.huge then
        return nil
    end
    local affected
    if amount < 0 and not allowNegative then
        affected = MySQL.update.await(
            'UPDATE trucker_companies SET balance = balance - ? WHERE id = ? AND balance >= ?',
            { -amount, companyId, -amount }
        )
    else
        affected = MySQL.update.await(
            'UPDATE trucker_companies SET balance = balance + ? WHERE id = ?',
            { amount, companyId }
        )
    end
    if not affected or affected == 0 then return nil end
    return MySQL.scalar.await(
        'SELECT balance FROM trucker_companies WHERE id = ? LIMIT 1',
        { companyId }
    )
end

function DB_SetCompanyRecruiting(companyId, isRecruiting)
    MySQL.update.await(
        'UPDATE trucker_companies SET is_recruiting = ? WHERE id = ?',
        { isRecruiting and 1 or 0, companyId }
    )
end

function DB_DeleteCompany(companyId)
    -- CASCADE deleta members e vehicles automaticamente
    MySQL.query.await('DELETE FROM trucker_companies WHERE id = ?', { companyId })
end

-- Deleta a empresa SOMENTE se não houver empréstimo ativo com saldo (checagem atômica no SQL).
-- Retorna linhas afetadas (0 = tem empréstimo ativo ou já deletada).
function DB_DeleteCompanyIfNoActiveLoan(companyId)
    return MySQL.update.await(
        [[DELETE FROM trucker_companies
          WHERE id = ?
            AND NOT EXISTS (SELECT 1 FROM trucker_loans l
                            WHERE l.company_id = ? AND l.status IN ('active','defaulted') AND l.remaining_balance > 0)]],
        { companyId, companyId }
    )
end

function DB_GetRecruitingCompanies()
    return MySQL.query.await(
        'SELECT c.*, COUNT(m.citizenid) as member_count FROM trucker_companies c LEFT JOIN trucker_company_members m ON m.company_id = c.id WHERE c.is_recruiting = 1 GROUP BY c.id'
    )
end

-- Adiciona XP à empresa e retorna { company_xp, company_level } atuais
function DB_AddCompanyXP(companyId, xp)
    MySQL.update.await(
        'UPDATE trucker_companies SET company_xp = company_xp + ? WHERE id = ?',
        { xp, companyId }
    )
    return MySQL.single.await(
        'SELECT company_xp, company_level FROM trucker_companies WHERE id = ? LIMIT 1',
        { companyId }
    )
end

-- Atualiza level da empresa (chamado no level-up; XP acumulado não é alterado)
function DB_SetCompanyLevel(companyId, level)
    MySQL.update.await(
        'UPDATE trucker_companies SET company_level = ? WHERE id = ?',
        { level, companyId }
    )
end

-- ============================================================
-- MEMBERS
-- ============================================================

function DB_AddMember(companyId, citizenId, role)
    role = role or 'driver'
    return MySQL.insert.await(
        'INSERT INTO trucker_company_members (citizenid, company_id, role) VALUES (?, ?, ?)',
        { citizenId, companyId, role }
    )
end

function DB_RemoveMember(citizenId)
    MySQL.query.await(
        'DELETE FROM trucker_company_members WHERE citizenid = ?',
        { citizenId }
    )
end

function DB_GetMembers(companyId)
    return MySQL.query.await(
        'SELECT * FROM trucker_company_members WHERE company_id = ?',
        { companyId }
    )
end

function DB_GetMember(citizenId)
    return MySQL.single.await(
        'SELECT * FROM trucker_company_members WHERE citizenid = ? LIMIT 1',
        { citizenId }
    )
end

-- ============================================================
-- VEHICLES
-- ============================================================

function DB_RegisterVehicle(companyId, plate, model, vehicleType)
    return MySQL.insert.await(
        'INSERT IGNORE INTO trucker_company_vehicles (plate, company_id, model, vehicle_type) VALUES (?, ?, ?, ?)',
        { companyId, plate, model, vehicleType }
    )
end

function DB_VehicleExists(plate)
    return MySQL.scalar.await(
        'SELECT 1 FROM trucker_company_vehicles WHERE plate = ?',
        { plate }
    ) ~= nil
end

function DB_RemoveVehicle(plate)
    MySQL.query.await(
        'DELETE FROM trucker_company_vehicles WHERE plate = ?',
        { plate }
    )
end

function DB_GetVehicles(companyId)
    return MySQL.query.await(
        'SELECT * FROM trucker_company_vehicles WHERE company_id = ?',
        { companyId }
    )
end

function DB_SetVehicleStatus(plate, status)
    MySQL.update.await(
        'UPDATE trucker_company_vehicles SET status = ? WHERE plate = ?',
        { status, plate }
    )
end

-- ============================================================
-- JOBS
-- ============================================================

function DB_InsertJob(job, convoyId)
    local cargoType = tonumber(job.cargo_type)
    if not cargoType and type(job.cargo_type) == 'string' then
        local adrMap = {
            ['explosives'] = 1,
            ['gases'] = 2,
            ['flammable_liquid'] = 3,
            ['flammable_solids'] = 4,
            ['toxic'] = 5,
            ['corrosives'] = 6,
            ['environmental'] = 5
        }
        cargoType = adrMap[job.cargo_type] or 0
    end
    cargoType = cargoType or 0

    return MySQL.insert.await(
        [[INSERT INTO trucker_jobs
          (id, origin_id, dest_id, cargo_item, trailer_model, base_payment, distance, expires_at, convoy_id, cargo_qty, weight, contract_type, cargo_type, fragile, valuable, fast, illegal)
          VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { job.id, job.origin_id, job.dest_id, job.cargo_item, job.trailer_model,
          job.base_payment, job.distance, job.expires_at, convoyId or nil, job.cargo_qty or 1, job.weight or 80,
          tonumber(job.contract_type) or 0, cargoType, tonumber(job.fragile) or 0, tonumber(job.valuable) or 0, tonumber(job.fast) or 0, tonumber(job.illegal) or 0 }
    )
end

function DB_GetAvailableJobs()
    return MySQL.query.await(
        "SELECT *, UNIX_TIMESTAMP(expires_at) as expires_at_unix, UNIX_TIMESTAMP(created_at) as created_at_unix FROM trucker_jobs WHERE status = 'available' AND expires_at > NOW()"
    )
end

function DB_GetActiveJobByPlayer(citizenId)
    return MySQL.single.await(
        "SELECT *, UNIX_TIMESTAMP(expires_at) as expires_at_unix, UNIX_TIMESTAMP(accepted_at) as accepted_at_unix FROM trucker_jobs WHERE assigned_citizenid = ? AND status = 'active' LIMIT 1",
        { citizenId }
    )
end

-- Retorna o número de linhas afetadas (0 = job indisponível/expirado)
function DB_AcceptJob(jobId, citizenId, companyId)
    return MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'active', assigned_citizenid = ?, company_id = ?, accepted_at = NOW() WHERE id = ? AND status = 'available' AND expires_at > NOW()",
        { citizenId, companyId, jobId }
    )
end

-- Retorna o número de linhas afetadas (0 = já concluído / não estava ativo)
function DB_CompleteJob(jobId)
    return MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'completed', completed_at = NOW() WHERE id = ? AND status = 'active'",
        { jobId }
    )
end

function DB_AbandonJob(jobId, citizenId)
    -- Se expirado → 'expired'; senão → 'available' de volta
    MySQL.update.await(
        [[UPDATE trucker_jobs
          SET status = IF(expires_at < NOW(), 'expired', 'available'),
              assigned_citizenid = NULL,
              company_id = NULL,
              accepted_at = NULL
          WHERE id = ? AND assigned_citizenid = ?]],
        { jobId, citizenId }
    )
end

function DB_ExpireStaleJobs()
    MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'expired' WHERE status IN ('available','active') AND expires_at < NOW()"
    )
end

function DB_CountActiveJobs()
    return MySQL.scalar.await(
        "SELECT COUNT(*) FROM trucker_jobs WHERE status = 'available'"
    ) or 0
end

-- ============================================================
-- PLAYER STATS
-- ============================================================

-- Upsert com log de erro (antes o erro era engolido silenciosamente)
local function SafeUpsertPlayerStats(citizenId)
    local ok, err = pcall(DB_UpsertPlayerStats, citizenId)
    if not ok then
        print(('[aurp_trucker] ERRO DB_UpsertPlayerStats(%s): %s'):format(tostring(citizenId), tostring(err)))
    end
end

function DB_GetPlayerStats(citizenId)
    SafeUpsertPlayerStats(citizenId)
    return MySQL.single.await(
        'SELECT * FROM trucker_player_progression WHERE citizenid = ? LIMIT 1',
        { citizenId }
    )
end

function DB_UpsertPlayerStats(citizenId)
    -- Cria registro se não existir (chamado no onPlayerLoaded)
    MySQL.insert.await(
        'INSERT IGNORE INTO trucker_player_progression (citizenid) VALUES (?)',
        { citizenId }
    )
end

function DB_AddPlayerStats(citizenId, earnings, distance)
    SafeUpsertPlayerStats(citizenId)
    MySQL.update.await(
        [[UPDATE trucker_player_progression
          SET total_earnings = total_earnings + ?,
              total_deliveries = total_deliveries + 1,
              total_distance = total_distance + ?
          WHERE citizenid = ?]],
        { tonumber(earnings) or 0, tonumber(distance) or 0.0, citizenId }
    )
end

-- ============================================================
-- PROGRESSION (XP, Level, Skills)
-- ============================================================

-- Adiciona XP e retorna o estado atual do jogador
function DB_AddXP(citizenId, xp)
    SafeUpsertPlayerStats(citizenId)
    MySQL.update.await(
        'UPDATE trucker_player_progression SET xp = xp + ? WHERE citizenid = ?',
        { tonumber(xp) or 0, citizenId }
    )
    return MySQL.single.await(
        'SELECT xp, level, rank, skill_points FROM trucker_player_progression WHERE citizenid = ? LIMIT 1',
        { citizenId }
    )
end

-- Atualiza level, rank e concede skill points (chamado no level-up)
function DB_SetLevelData(citizenId, level, rank, skillPointsToAdd)
    MySQL.update.await(
        [[UPDATE trucker_player_progression
          SET level = ?, rank = ?, skill_points = skill_points + ?
          WHERE citizenid = ?]],
        { level, rank, skillPointsToAdd, citizenId }
    )
end

-- Retorna todas as skills do jogador
function DB_GetSkills(citizenId)
    return MySQL.query.await(
        'SELECT skill_type, skill_level FROM trucker_player_skills WHERE citizenid = ?',
        { citizenId }
    )
end

-- Insere ou atualiza nível de skill
function DB_UpsertSkill(citizenId, skillType, newLevel)
    MySQL.insert.await(
        [[INSERT INTO trucker_player_skills (citizenid, skill_type, skill_level)
          VALUES (?, ?, ?)
          ON DUPLICATE KEY UPDATE skill_level = VALUES(skill_level)]],
        { citizenId, skillType, newLevel }
    )

    local colMap = {
        distance = 'distance_skill',
        valuable = 'valuable_skill',
        fragile = 'fragile_skill',
        fast = 'fast_skill',
        speed = 'fast_skill',
        product_type = 'product_type',
        illegal = 'illegal_skill',
    }
    local col = colMap[skillType]
    if col then
        MySQL.update.await(
            string.format('UPDATE trucker_player_progression SET %s = ? WHERE citizenid = ?', col),
            { newLevel, citizenId }
        )
    end
end

-- Gasta 1 skill point — retorna número de linhas afetadas (0 = falhou, ponto já foi gasto)
function DB_SpendSkillPoint(citizenId)
    return MySQL.update.await(
        'UPDATE trucker_player_progression SET skill_points = skill_points - 1 WHERE citizenid = ? AND skill_points >= 1',
        { citizenId }
    )
end

-- ============================================================
-- INDUSTRY STATE
-- ============================================================

function DB_GetIndustryState(industryId)
    return MySQL.query.await(
        'SELECT * FROM trucker_industry_state WHERE industry_id = ?',
        { industryId }
    )
end

function DB_GetAllIndustryState()
    return MySQL.query.await('SELECT * FROM trucker_industry_state')
end

function DB_UpsertIndustryState(industryId, item, entryType, price, stock)
    MySQL.insert.await(
        [[INSERT INTO trucker_industry_state (industry_id, item, entry_type, current_price, current_stock)
          VALUES (?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE current_price = VALUES(current_price), current_stock = VALUES(current_stock)]],
        { industryId, item, entryType, price, stock }
    )
end

function DB_UpdateIndustryStock(industryId, item, entryType, deltaStock)
    MySQL.update.await(
        [[UPDATE trucker_industry_state
          SET current_stock = GREATEST(0, current_stock + ?)
          WHERE industry_id = ? AND item = ? AND entry_type = ?]],
        { deltaStock, industryId, item, entryType }
    )
end

function DB_UpdateIndustryPrice(industryId, item, entryType, newPrice)
    MySQL.update.await(
        'UPDATE trucker_industry_state SET current_price = ? WHERE industry_id = ? AND item = ? AND entry_type = ?',
        { newPrice, industryId, item, entryType }
    )
end

-- ============================================================
-- INFRACTIONS
-- ============================================================

function DB_RecordInfraction(citizenId, jobId, infractionType, reason, issuedBy)
    return MySQL.insert.await(
        'INSERT INTO trucker_infractions (citizenid, job_id, infraction_type, reason, issued_by) VALUES (?, ?, ?, ?, ?)',
        { citizenId, jobId, infractionType, reason, issuedBy }
    )
end

function DB_GetInfractions(citizenId)
    return MySQL.query.await(
        'SELECT * FROM trucker_infractions WHERE citizenid = ? ORDER BY created_at DESC',
        { citizenId }
    )
end

-- ============================================================
-- LOANS
-- ============================================================

function DB_CreateLoan(citizenId, companyId, vehiclePlate, amount, totalToPay, monthlyPayment, nextPaymentAt)
    return MySQL.insert.await(
        [[INSERT INTO trucker_loans
            (citizenid, company_id, vehicle_plate, amount, remaining_balance, monthly_payment, status, next_payment_at)
          VALUES (?, ?, ?, ?, ?, ?, 'active', FROM_UNIXTIME(?))]],
        { citizenId, companyId, vehiclePlate, amount, totalToPay, monthlyPayment, nextPaymentAt }
    )
end

-- "Ativo" aqui = dívida em aberto: 'active' OU 'defaulted' (inadimplente). Um empréstimo
-- inadimplente continua bloqueando novos empréstimos/venda da empresa e pode ser quitado.
function DB_GetActiveLoan(citizenId)
    return MySQL.single.await(
        [[SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at
          FROM trucker_loans
          WHERE citizenid = ? AND company_id IS NULL AND status IN ('active','defaulted')
          LIMIT 1]],
        { citizenId }
    )
end

function DB_GetActiveCompanyLoan(companyId)
    return MySQL.single.await(
        [[SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at
          FROM trucker_loans
          WHERE company_id = ? AND status IN ('active','defaulted')
          LIMIT 1]],
        { companyId }
    )
end

-- Retorna o nº de linhas afetadas (0 = empréstimo não está mais 'active', ex.: já quitado
-- por uma chamada concorrente). Chamadores devem checar e reverter efeitos colaterais.
function DB_UpdateLoanBalance(loanId, newBalance, newStatus, nextPaymentAt)
    -- nextPaymentAt may be nil (for paid loans); FROM_UNIXTIME(NULL) = NULL in MySQL
    return MySQL.update.await(
        [[UPDATE trucker_loans
          SET remaining_balance = ?, status = ?, next_payment_at = FROM_UNIXTIME(?),
              missed_payments = IF(? = 'active', 0, missed_payments)
          WHERE id = ? AND status IN ('active','defaulted')]],
        { newBalance, newStatus, nextPaymentAt, newStatus, loanId }
    )
end

-- Registra uma parcela perdida (multa aplicada): guarda contador e, se atingiu o limite,
-- marca 'defaulted'. Só atua em empréstimos 'active' (retorna linhas afetadas).
function DB_RecordLoanMiss(loanId, newBalance, newStatus, nextPaymentAt, missedPayments)
    return MySQL.update.await(
        [[UPDATE trucker_loans
          SET remaining_balance = ?, status = ?, next_payment_at = FROM_UNIXTIME(?), missed_payments = ?
          WHERE id = ? AND status = 'active']],
        { newBalance, newStatus, nextPaymentAt, missedPayments, loanId }
    )
end

-- Remove um empréstimo recém-criado cujo desembolso falhou (rollback)
function DB_DeleteLoan(loanId)
    MySQL.update.await('DELETE FROM trucker_loans WHERE id = ?', { loanId })
end

function DB_GetOverdueLoans()
    return MySQL.query.await(
        [[SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at_unix
          FROM trucker_loans
          WHERE next_payment_at < NOW() AND status = 'active']],
        {}
    )
end

function DB_GetLoanById(loanId)
    return MySQL.single.await(
        [[SELECT *, UNIX_TIMESTAMP(next_payment_at) as next_payment_at_unix
          FROM trucker_loans WHERE id = ? LIMIT 1]],
        { loanId }
    )
end

-- ============================================================
-- REPO ORDERS
-- ============================================================

function DB_InsertRepoOrder(vehiclePlate, vehicleModel, vehicleValue, vehicleOwnerCitizenId,
                             missionType, locationZone, payment, expiresAt, loanId)
    -- companyId always nil at insert — set via DB_AcceptRepoOrder
    return MySQL.insert.await(
        [[INSERT IGNORE INTO trucker_repo_orders
            (vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
             mission_type, location_zone, payment, expires_at, loan_id, status)
          VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?, 'available')]],
        { vehiclePlate, vehicleModel, vehicleValue, vehicleOwnerCitizenId,
          missionType, locationZone, payment, expiresAt, loanId }
    )
end

function DB_GetAvailableRepoOrders()
    return MySQL.query.await(
        [[SELECT id, vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
                 mission_type, location_zone, payment, status, loan_id,
                 UNIX_TIMESTAMP(expires_at) as expires_at_unix,
                 UNIX_TIMESTAMP(created_at) as created_at_unix
          FROM trucker_repo_orders
          WHERE status = 'available' AND expires_at > NOW()
          ORDER BY created_at DESC]]
    )
end

function DB_CountAvailableNpcOrders()
    return MySQL.scalar.await(
        [[SELECT COUNT(*) FROM trucker_repo_orders
          WHERE status = 'available' AND vehicle_owner_citizenid IS NULL AND expires_at > NOW()]]
    ) or 0
end

function DB_GetActiveRepoOrder(citizenId)
    return MySQL.single.await(
        [[SELECT id, vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
                 mission_type, location_zone, payment, status, company_id, loan_id,
                 assigned_citizenid,
                 UNIX_TIMESTAMP(expires_at) as expires_at_unix,
                 UNIX_TIMESTAMP(created_at) as created_at_unix
          FROM trucker_repo_orders
          WHERE assigned_citizenid = ? AND status = 'active' LIMIT 1]],
        { citizenId }
    )
end

function DB_AcceptRepoOrder(orderId, citizenId, companyId)
    return MySQL.update.await(
        [[UPDATE trucker_repo_orders
          SET status = 'active', assigned_citizenid = ?, company_id = ?, accepted_at = NOW()
          WHERE id = ? AND status = 'available']],
        { citizenId, companyId, orderId }
    )
end

function DB_UpdateRepoOrderStatus(orderId, newStatus, assignedCitizenId, companyId)
    return MySQL.update.await(
        [[UPDATE trucker_repo_orders
          SET status = ?, assigned_citizenid = ?, company_id = ?
          WHERE id = ?]],
        { newStatus, assignedCitizenId, companyId, orderId }
    )
end

-- C-13: Retorna rowsAffected; WHERE status='active' garante idempotência atômica
function DB_CompleteRepoOrder(orderId, completedAt)
    return MySQL.update.await(
        [[UPDATE trucker_repo_orders
          SET status = 'completed', completed_at = FROM_UNIXTIME(?)
          WHERE id = ? AND status = 'active']],
        { completedAt, orderId }
    )
end

-- Conclusão atômica: só se a ordem está ativa E atribuída a este jogador (retorna linhas afetadas)
function DB_CompleteRepoOrderByAgent(orderId, citizenId, completedAt)
    return MySQL.update.await(
        [[UPDATE trucker_repo_orders
          SET status = 'completed', completed_at = FROM_UNIXTIME(?)
          WHERE id = ? AND status = 'active' AND assigned_citizenid = ?]],
        { completedAt, orderId, citizenId }
    )
end

-- Segundos desde a aceitação da ordem (nil se não registrado, ex.: ordens anteriores à migration)
function DB_GetRepoOrderElapsed(orderId)
    return MySQL.scalar.await(
        'SELECT TIMESTAMPDIFF(SECOND, accepted_at, NOW()) FROM trucker_repo_orders WHERE id = ? LIMIT 1',
        { orderId }
    )
end

function DB_ExpireRepoOrders()
    MySQL.update.await(
        [[UPDATE trucker_repo_orders
          SET status = 'expired'
          WHERE expires_at < NOW() AND status IN ('available', 'active')]]
    )
end

function DB_GetRepoOrderById(orderId)
    return MySQL.single.await(
        [[SELECT id, vehicle_plate, vehicle_model, vehicle_value, vehicle_owner_citizenid,
                 mission_type, location_zone, payment, status, company_id, loan_id,
                 assigned_citizenid,
                 UNIX_TIMESTAMP(expires_at) as expires_at_unix,
                 UNIX_TIMESTAMP(created_at) as created_at_unix
          FROM trucker_repo_orders WHERE id = ? LIMIT 1]],
        { orderId }
    )
end

-- ============================================================
-- TRUCK SIMULATION — FUEL / FATIGUE / FLEET UPGRADES
-- ============================================================

function DB_GetVehicleModel(plate)
    return MySQL.single.await(
        'SELECT model FROM trucker_company_vehicles WHERE plate = ? LIMIT 1',
        { plate }
    )
end

function DB_GetVehicleFuel(plate)
    local row = MySQL.single.await(
        'SELECT fuel_level FROM trucker_company_vehicles WHERE plate = ? LIMIT 1',
        { plate }
    )
    return row and row.fuel_level or 100.0
end

function DB_SetVehicleFuel(plate, fuel)
    MySQL.update.await(
        'UPDATE trucker_company_vehicles SET fuel_level = ? WHERE plate = ?',
        { math.max(0.0, math.min(100.0, fuel)), plate }
    )
end

function DB_GetFatigue(citizenId)
    local row = MySQL.single.await(
        'SELECT fatigue FROM trucker_player_progression WHERE citizenid = ? LIMIT 1',
        { citizenId }
    )
    return row and row.fatigue or 0.0
end

function DB_SetFatigue(citizenId, fatigue)
    MySQL.update.await(
        'UPDATE trucker_player_progression SET fatigue = ? WHERE citizenid = ?',
        { math.max(0.0, math.min(100.0, fatigue)), citizenId }
    )
end

function DB_GetFleetUpgrades(companyId)
    local row = MySQL.single.await(
        'SELECT fleet_upgrades FROM trucker_companies WHERE id = ? LIMIT 1',
        { companyId }
    )
    if not row or not row.fleet_upgrades then return {} end
    return json.decode(row.fleet_upgrades) or {}
end

function DB_SetFleetUpgrades(companyId, upgrades)
    MySQL.update.await(
        'UPDATE trucker_companies SET fleet_upgrades = ? WHERE id = ?',
        { json.encode(upgrades), companyId }
    )
end

-- ============================================================
-- INDUSTRY OWNERSHIP
-- ============================================================

-- Retorna o ownership de uma indústria (ou nil se não tem dono)
function DB_GetIndustryOwner(industryId)
    return MySQL.single.await(
        'SELECT * FROM trucker_industry_ownership WHERE industry_id = ? LIMIT 1',
        { industryId }
    )
end

-- Insere ownership de uma nova compra.
-- USA INSERT ... ON DUPLICATE KEY UPDATE para NÃO zerar production_level/npc_workers/total_earned
function DB_SetIndustryOwner(industryId, ownerCitizenId, companyId, purchasePrice)
    MySQL.insert.await(
        [[INSERT INTO trucker_industry_ownership
            (industry_id, owner_citizenid, company_id, purchase_price)
          VALUES (?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE
            owner_citizenid = VALUES(owner_citizenid),
            company_id      = VALUES(company_id),
            purchase_price  = VALUES(purchase_price)]],
        { industryId, ownerCitizenId, companyId, purchasePrice }
    )
end

-- Reivindica atomicamente uma indústria: INSERT sem upsert. A PK (industry_id) garante que
-- só uma empresa vence; retorna false se já existe dono (ou em erro de DB).
function DB_TryClaimIndustry(industryId, ownerCitizenId, companyId, purchasePrice)
    local ok, affected = pcall(MySQL.update.await,
        [[INSERT IGNORE INTO trucker_industry_ownership
            (industry_id, owner_citizenid, company_id, purchase_price)
          VALUES (?, ?, ?, ?)]],
        { industryId, ownerCitizenId, companyId, purchasePrice }
    )
    return ok and (affected or 0) > 0
end

-- Remove ownership (venda/abandono)
function DB_ClearIndustryOwner(industryId)
    MySQL.query.await(
        'DELETE FROM trucker_industry_ownership WHERE industry_id = ?',
        { industryId }
    )
end

-- Soma ao total_earned da indústria
function DB_AddOwnerEarnings(industryId, amount)
    MySQL.update.await(
        'UPDATE trucker_industry_ownership SET total_earned = total_earned + ? WHERE industry_id = ?',
        { amount, industryId }
    )
end

-- Retorna todas as indústrias de uma empresa
function DB_GetOwnedByCompany(companyId)
    return MySQL.query.await(
        'SELECT * FROM trucker_industry_ownership WHERE company_id = ?',
        { companyId }
    )
end

-- Retorna todas as ownerships (para cache no init)
function DB_GetAllIndustryOwners()
    return MySQL.query.await('SELECT * FROM trucker_industry_ownership')
end

-- ============================================================
-- NPC FAIL-SAFE
-- ============================================================

-- Retorna itens de consumo com stock = 0 e last_npc_fill_at expirado (ou NULL)
-- NOTA: MySQL não aceita ? como quantidade em INTERVAL. Usar TIMESTAMPADD(SECOND, -?, NOW()).
function DB_GetStarvedConsumptionItems(thresholdSeconds)
    return MySQL.query.await(
        [[SELECT industry_id, item, current_stock, last_npc_fill_at
          FROM trucker_industry_state
          WHERE entry_type = 'consumption'
            AND current_stock = 0
            AND (last_npc_fill_at IS NULL
                 OR last_npc_fill_at < TIMESTAMPADD(SECOND, -?, NOW()))]],
        { thresholdSeconds }
    )
end

-- Marca o momento do NPC fill para evitar spam de refill
function DB_SetNpcFillTime(industryId, item)
    MySQL.update.await(
        [[UPDATE trucker_industry_state
          SET last_npc_fill_at = NOW()
          WHERE industry_id = ? AND item = ? AND entry_type = 'consumption']],
        { industryId, item }
    )
end

-- ============================================================
-- PARTIES
-- ============================================================

function DB_CreateParty(partyId, leaderCid, maxSize)
    MySQL.insert.await(
        'INSERT INTO trucker_parties (id, leader_cid, max_size) VALUES (?, ?, ?)',
        { partyId, leaderCid, maxSize }
    )
end

function DB_GetParty(partyId)
    return MySQL.single.await(
        'SELECT * FROM trucker_parties WHERE id = ? LIMIT 1',
        { partyId }
    )
end

function DB_SetPartyStatus(partyId, status)
    MySQL.update.await(
        'UPDATE trucker_parties SET status = ? WHERE id = ?',
        { status, partyId }
    )
end

-- ============================================================
-- CONVOY JOBS
-- ============================================================

function DB_CreateConvoy(convoyId, partyId, bonusMult, totalCount)
    MySQL.insert.await([[
        INSERT INTO trucker_convoy_jobs (id, party_id, bonus_mult, total_count, active_count, status, started_at)
        VALUES (?, ?, ?, ?, ?, 'active', NOW())
    ]], { convoyId, partyId, bonusMult, totalCount, totalCount })
end

function DB_GetActiveConvoys()
    return MySQL.query.await(
        "SELECT * FROM trucker_convoy_jobs WHERE status = 'active'"
    ) or {}
end

function DB_SetConvoyStatus(convoyId, status)
    local extra = (status == 'completed' or status == 'cancelled') and ', completed_at = NOW()' or ''
    MySQL.update.await(
        ('UPDATE trucker_convoy_jobs SET status = ? %s WHERE id = ?'):format(extra),
        { status, convoyId }
    )
end

function DB_SetConvoyBonusMult(convoyId, bonusMult)
    MySQL.update.await(
        'UPDATE trucker_convoy_jobs SET bonus_mult = ? WHERE id = ?',
        { bonusMult, convoyId }
    )
end

-- ============================================================
-- CONVOY MEMBERS
-- ============================================================

function DB_CreateConvoyMember(convoyId, citizenid, jobId)
    MySQL.insert.await([[
        INSERT INTO trucker_convoy_members (convoy_id, citizenid, job_id, status)
        VALUES (?, ?, ?, 'pending')
    ]], { convoyId, citizenid, jobId })
end

function DB_GetConvoyMember(convoyId, citizenid)
    return MySQL.single.await(
        'SELECT * FROM trucker_convoy_members WHERE convoy_id = ? AND citizenid = ? LIMIT 1',
        { convoyId, citizenid }
    )
end

function DB_SetConvoyMemberStatus(convoyId, citizenid, status)
    MySQL.update.await(
        'UPDATE trucker_convoy_members SET status = ? WHERE convoy_id = ? AND citizenid = ?',
        { status, convoyId, citizenid }
    )
end

function DB_GetConvoyMembers(convoyId)
    return MySQL.query.await(
        'SELECT * FROM trucker_convoy_members WHERE convoy_id = ?',
        { convoyId }
    ) or {}
end

-- Libera (expira) os jobs ainda pendentes/ativos de um convoy cancelado.
function DB_ReleaseConvoyJobs(convoyId)
    return MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'expired' WHERE convoy_id = ? AND status IN ('available','active')",
        { convoyId }
    )
end

-- Retorna job completo incluindo convoy_id (usado por JobService.Complete para detectar convoy)
function DB_GetJobWithConvoy(jobId)
    return MySQL.single.await(
        'SELECT id, base_payment, distance, cargo_item, convoy_id FROM trucker_jobs WHERE id = ? LIMIT 1',
        { jobId }
    )
end

-- ============================================================
-- CONVOY PAYMENTS (histórico por membro)
-- ============================================================

-- Registra o pagamento de um membro ao final do convoy
function DB_RecordConvoyPayment(convoyId, citizenid, amount, bonusMult, completedCount, totalCount)
    MySQL.insert.await(
        [[INSERT INTO trucker_convoy_payments
            (convoy_id, citizenid, amount, bonus_mult, completed_count, total_count)
          VALUES (?, ?, ?, ?, ?, ?)]],
        { convoyId, citizenid, amount, bonusMult, completedCount, totalCount }
    )
end

-- Reivindica atomicamente o pagamento de um membro (INSERT IGNORE + UNIQUE convoy_id/citizenid).
-- Retorna true somente se este chamador inseriu o registro (pode pagar); false se já reivindicado.
function DB_ClaimConvoyPayment(convoyId, citizenid, amount, bonusMult, completedCount, totalCount)
    local ok, affected = pcall(MySQL.update.await,
        [[INSERT IGNORE INTO trucker_convoy_payments
            (convoy_id, citizenid, amount, bonus_mult, completed_count, total_count)
          VALUES (?, ?, ?, ?, ?, ?)]],
        { convoyId, citizenid, amount, bonusMult, completedCount, totalCount }
    )
    if not ok then
        print(('[aurp_trucker] ERRO DB_ClaimConvoyPayment: %s'):format(tostring(affected)))
        return false
    end
    return (tonumber(affected) or 0) > 0
end

-- Retorna os últimos pagamentos de convoy de um jogador (máx 50)
function DB_GetConvoyHistory(citizenid, limit)
    limit = math.min(tonumber(limit) or 20, 50)
    return MySQL.query.await([[
        SELECT cp.convoy_id, cp.amount, cp.bonus_mult,
               cp.completed_count, cp.total_count,
               cp.created_at
        FROM trucker_convoy_payments cp
        WHERE cp.citizenid = ?
        ORDER BY cp.created_at DESC
        LIMIT ?
    ]], { citizenid, limit }) or {}
end

-- ============================================================
-- ILLEGAL DELIVERIES
-- ============================================================

-- Insere job ilegal na tabela trucker_jobs diretamente como 'active' (evita janela de corrida)
function DB_InsertIllegalJob(job)
    MySQL.insert.await(
        [[INSERT INTO trucker_jobs
          (id, origin_id, dest_id, cargo_item, trailer_model, base_payment,
           distance, expires_at, illegal_type, status, assigned_citizenid, accepted_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?, 'active', ?, NOW())]],
        {
            job.id,
            job.origin_id,
            job.dest_id,
            job.cargo_item,
            job.trailer_model,
            job.base_payment,
            job.distance,
            job.expires_at,
            job.illegal_type,
            job.citizenid,
        }
    )
end

-- Expira um job imediatamente (usado em apreensões ilegais)
-- Diferente de DB_AbandonJob: não retorna o job para 'available'
function DB_ExpireJob(jobId)
    MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'expired' WHERE id = ?",
        { jobId }
    )
end

-- ============================================================
-- NPC DRIVERS
-- ============================================================

function DB_InsertNpcDriver(driver)
    return MySQL.insert.await(
        [[INSERT INTO trucker_npc_drivers
          (id, company_id, name, skill_level, salary, satisfaction, last_tenure_check)
          VALUES (?, ?, ?, ?, ?, ?, ?)]],
        { driver.id, driver.company_id, driver.name, driver.skill_level,
          driver.salary, driver.satisfaction, os.time() }
    )
end

function DB_GetNpcDriversByCompany(companyId)
    return MySQL.query.await(
        "SELECT * FROM trucker_npc_drivers WHERE company_id = ? AND status NOT IN ('fired','quit')",
        { companyId }
    ) or {}
end

function DB_GetAllActiveNpcDrivers()
    return MySQL.query.await(
        "SELECT * FROM trucker_npc_drivers WHERE status IN ('idle','working','resting')"
    ) or {}
end

function DB_UpdateNpcDriverStatus(id, status, activeJobId)
    MySQL.update.await(
        'UPDATE trucker_npc_drivers SET status = ?, active_job_id = ? WHERE id = ?',
        { status, activeJobId, id }
    )
end

-- xpGain e totalEarningsGain podem ser positivos; satisfactionDelta pode ser negativo
function DB_UpdateNpcDriverStats(id, xpGain, satisfactionDelta, totalEarningsGain)
    MySQL.update.await(
        [[UPDATE trucker_npc_drivers
          SET xp             = xp + ?,
              satisfaction   = GREATEST(0, LEAST(100, satisfaction + ?)),
              total_earnings = total_earnings + ?
          WHERE id = ?]],
        { xpGain, satisfactionDelta, totalEarningsGain, id }
    )
end

function DB_UpdateNpcDriverSatisfaction(id, satisfactionDelta)
    MySQL.update.await(
        'UPDATE trucker_npc_drivers SET satisfaction = GREATEST(0, LEAST(100, satisfaction + ?)) WHERE id = ?',
        { satisfactionDelta, id }
    )
end

function DB_UpdateNpcDriverTenure(id, tenureDays, lastTenureCheck)
    MySQL.update.await(
        'UPDATE trucker_npc_drivers SET tenure_days = ?, last_tenure_check = ? WHERE id = ?',
        { tenureDays, lastTenureCheck, id }
    )
end

function DB_UpdateNpcDriverSalary(id, salary)
    MySQL.update.await(
        'UPDATE trucker_npc_drivers SET salary = ? WHERE id = ?',
        { salary, id }
    )
end

function DB_SetNpcDriverQuit(id)
    MySQL.update.await(
        "UPDATE trucker_npc_drivers SET status = 'quit', active_job_id = NULL WHERE id = ?",
        { id }
    )
end

function DB_SetNpcDriverResting(id, restingUntil)
    MySQL.update.await(
        "UPDATE trucker_npc_drivers SET status = 'resting', active_job_id = NULL, resting_until = ? WHERE id = ?",
        { restingUntil, id }
    )
end

function DB_UpdateNpcDriverSkill(id, skillLevel)
    MySQL.update.await(
        'UPDATE trucker_npc_drivers SET skill_level = ? WHERE id = ?',
        { skillLevel, id }
    )
end

-- NPC Jobs

function DB_InsertNpcJob(npcJob)
    return MySQL.insert.await(
        [[INSERT INTO trucker_npc_jobs
          (id, driver_id, company_id, origin_id, dest_id, cargo_item,
           base_payment, distance, illegal, assigned_at, expected_end_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { npcJob.id, npcJob.driver_id, npcJob.company_id,
          npcJob.origin_id, npcJob.dest_id, npcJob.cargo_item,
          npcJob.base_payment, npcJob.distance, npcJob.illegal,
          npcJob.assigned_at, npcJob.expected_end_at }
    )
end

function DB_UpdateNpcJobStatus(id, status, earnings)
    MySQL.update.await(
        'UPDATE trucker_npc_jobs SET status = ?, earnings = ? WHERE id = ?',
        { status, earnings or 0, id }
    )
end

function DB_GetNpcJobsByStatus(status)
    return MySQL.query.await(
        'SELECT * FROM trucker_npc_jobs WHERE status = ?',
        { status }
    ) or {}
end

function DB_GetOneAvailableJobForNpc()
    return MySQL.single.await(
        "SELECT * FROM trucker_jobs WHERE status = 'available' ORDER BY RAND() LIMIT 1"
    )
end

function DB_GetOneAvailableIllegalJobForNpc()
    -- [L2] trucker_illegal_deliveries não existe no schema — jobs ilegais usam
    -- trucker_jobs com coluna illegal_type; função substituída por query correta
    return MySQL.single.await(
        "SELECT * FROM trucker_jobs WHERE status = 'available' AND illegal_type IS NOT NULL ORDER BY RAND() LIMIT 1"
    )
end

-- Empresa — Reputação (lê de volta e atualiza cache)

function DB_UpdateCompanyReputation(companyId, delta)
    MySQL.update.await(
        'UPDATE trucker_companies SET reputation = GREATEST(0, LEAST(100, CAST(reputation AS SIGNED) + ?)) WHERE id = ?',
        { delta, companyId }
    )
    local row = MySQL.single.await(
        'SELECT reputation FROM trucker_companies WHERE id = ?',
        { companyId }
    )
    if VP_Trucker.Companies[companyId] and row then
        VP_Trucker.Companies[companyId].reputation = row.reputation
    end
end

function DB_SetNpcAllowIllegal(companyId, allowed)
    MySQL.update.await(
        'UPDATE trucker_companies SET allow_illegal_npc = ? WHERE id = ?',
        { allowed and 1 or 0, companyId }
    )
end

-- ============================================================
-- ADR CERTIFICATIONS
-- ============================================================

function DB_GetAdrCerts(citizenId)
    return MySQL.query.await(
        'SELECT adr_type, expires_at FROM trucker_adr_certs WHERE citizenid = ?',
        { citizenId }
    ) or {}
end

function DB_GetAdrCert(citizenId, adrType)
    return MySQL.single.await(
        'SELECT adr_type, expires_at FROM trucker_adr_certs WHERE citizenid = ? AND adr_type = ? LIMIT 1',
        { citizenId, adrType }
    )
end

function DB_UpsertAdrCert(citizenId, adrType, expiresAt)
    MySQL.update.await([[
        INSERT INTO trucker_adr_certs (citizenid, adr_type, expires_at)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE expires_at = VALUES(expires_at)
    ]], { citizenId, adrType, expiresAt })
end

-- ============================================================
-- CARGO THEFT
-- ============================================================

-- Salva a plate do caminhão no job ativo (chamado quando jogador entra no truck)
function DB_SetTruckPlate(jobId, plate)
    MySQL.update.await(
        'UPDATE trucker_jobs SET truck_plate = ? WHERE id = ?',
        { plate, jobId }
    )
end

-- Busca job ativo pela plate do caminhão (para roubo e validação)
function DB_GetActiveJobByPlate(plate)
    return MySQL.single.await(
        "SELECT * FROM trucker_jobs WHERE truck_plate = ? AND status = 'active' LIMIT 1",
        { plate }
    )
end

-- Busca qualquer job pelo ID (para cálculo de pagamento do ladrão)
function DB_GetJobById(jobId)
    return MySQL.single.await(
        'SELECT * FROM trucker_jobs WHERE id = ? LIMIT 1',
        { jobId }
    )
end

-- Marca job como falhado (carga roubada)
function DB_SetCargoFailed(jobId)
    MySQL.update.await(
        "UPDATE trucker_jobs SET status = 'failed' WHERE id = ?",
        { jobId }
    )
end

-- Atualiza GPS tracker de um veículo de empresa (por plate)
-- Reivindica atomicamente a instalação do GPS: só tem sucesso (true) se o veículo
-- pertence à empresa e ainda não tem tracker. Evita cobrança dupla em chamadas simultâneas.
function DB_ClaimGpsTracker(plate, companyId)
    local affected = MySQL.update.await(
        'UPDATE trucker_company_vehicles SET has_gps_tracker = 1 WHERE plate = ? AND company_id = ? AND has_gps_tracker = 0',
        { plate, companyId }
    )
    return (affected or 0) > 0
end

function DB_SetGpsTracker(plate, enabled)
    MySQL.update.await(
        'UPDATE trucker_company_vehicles SET has_gps_tracker = ? WHERE plate = ?',
        { enabled and 1 or 0, plate }
    )
end

-- Retorna se um veículo tem GPS tracker instalado
function DB_GetVehicleGps(plate)
    local row = MySQL.single.await(
        'SELECT has_gps_tracker FROM trucker_company_vehicles WHERE plate = ? LIMIT 1',
        { plate }
    )
    return row and row.has_gps_tracker == 1
end

-- Recupera jobs ativos com plate registrada (para CargoTrackingService.LoadFromDB)
function DB_GetActiveCargoJobs()
    return MySQL.query.await(
        "SELECT id, truck_plate, assigned_citizenid, base_payment FROM trucker_jobs WHERE status = 'active' AND truck_plate IS NOT NULL"
    ) or {}
end

-- ============================================================
-- SHOP STOCK ECOSYSTEM
-- ============================================================

function DB_GetAllShopStock()
    return MySQL.query.await('SELECT * FROM trucker_shop_stock') or {}
end

function DB_UpsertShopStock(shopId, itemName, data)
    MySQL.query.await([[
        INSERT INTO trucker_shop_stock (shop_id, item_name, current_stock, max_stock, min_threshold, reorder_qty, price_per_unit, linked_industry_type, management_type)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE max_stock = VALUES(max_stock), min_threshold = VALUES(min_threshold),
            reorder_qty = VALUES(reorder_qty), price_per_unit = VALUES(price_per_unit),
            linked_industry_type = VALUES(linked_industry_type)
    ]], {
        shopId, itemName,
        data.currentStock or data.maxStock or 100,
        data.maxStock or 200,
        data.minThreshold or 20,
        data.reorderQty or 50,
        data.pricePerUnit or 15,
        data.linkedType or 'food',
        data.managementType or 'npc',
    })
end

-- Atômico: só consome se current_stock >= qty
function DB_ConsumeShopStock(shopId, itemName, qty)
    local result = MySQL.update.await(
        'UPDATE trucker_shop_stock SET current_stock = current_stock - ? WHERE shop_id = ? AND item_name = ? AND current_stock >= ?',
        { qty, shopId, itemName, qty }
    )
    return result and result > 0
end

function DB_RestockShop(shopId, itemName, qty)
    MySQL.update.await(
        'UPDATE trucker_shop_stock SET current_stock = LEAST(max_stock, current_stock + ?), pending_contract_id = NULL, last_restock_at = NOW() WHERE shop_id = ? AND item_name = ?',
        { qty, shopId, itemName }
    )
end

function DB_GetLowStockShops()
    return MySQL.query.await(
        'SELECT * FROM trucker_shop_stock WHERE current_stock <= min_threshold AND pending_contract_id IS NULL'
    ) or {}
end

function DB_SetShopPendingContract(shopId, itemName, contractId)
    MySQL.update.await(
        'UPDATE trucker_shop_stock SET pending_contract_id = ? WHERE shop_id = ? AND item_name = ?',
        { contractId, shopId, itemName }
    )
end

function DB_ClearShopPendingContract(shopId, itemName)
    MySQL.update.await(
        'UPDATE trucker_shop_stock SET pending_contract_id = NULL WHERE shop_id = ? AND item_name = ?',
        { shopId, itemName }
    )
end

-- ============================================================
-- AUST TRUCKER STATS (Logística 2.0 Persistence)
-- ============================================================

function DB_GetAustTruckerStats(citizenId)
    local row = MySQL.single.await([[
        SELECT * FROM aust_trucker_stats WHERE citizenid = ? LIMIT 1
    ]], { citizenId })
    if not row then
        MySQL.insert.await([[
            INSERT IGNORE INTO aust_trucker_stats (citizenid, level, exp, deliveries)
            VALUES (?, 1, 0, 0)
        ]], { citizenId })
        return { citizenid = citizenId, level = 1, exp = 0, deliveries = 0 }
    end
    return row
end

function DB_UpdateAustTruckerStats(citizenId, addedExp, addedDeliveries)
    addedExp = tonumber(addedExp) or 0
    addedDeliveries = tonumber(addedDeliveries) or 0

    local current = DB_GetAustTruckerStats(citizenId)
    local newExp = (current.exp or 0) + addedExp
    local newDeliveries = (current.deliveries or 0) + addedDeliveries

    -- Progressão de nível: 1000 EXP por nível
    local newLevel = math.max(1, math.floor(newExp / 1000) + 1)

    MySQL.update.await([[
        UPDATE aust_trucker_stats
        SET level = ?, exp = ?, deliveries = ?
        WHERE citizenid = ?
    ]], { newLevel, newExp, newDeliveries, citizenId })

    return {
        level = newLevel,
        exp = newExp,
        deliveries = newDeliveries,
        levelsGained = math.max(0, newLevel - (current.level or 1))
    }
end

