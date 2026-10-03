-- aurp_trucker — import.sql
-- Arquivo de referência para instalação manual / reset do banco.
--
-- ⚠️  FONTE CANÔNICA: server/database.lua (array TABLES + MIGRATIONS)
--     Este arquivo é secundário. Ao adicionar tabelas, edite database.lua PRIMEIRO.
--     import.sql deve ser mantido em sincronia manualmente quando necessário.
--
-- Uso: SOURCE import.sql;   (apaga e recria todas as tabelas do zero)

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS trucker_convoy_payments;
DROP TABLE IF EXISTS trucker_convoy_members;
DROP TABLE IF EXISTS trucker_convoy_jobs;
DROP TABLE IF EXISTS trucker_parties;
DROP TABLE IF EXISTS trucker_repo_orders;
DROP TABLE IF EXISTS trucker_infractions;
DROP TABLE IF EXISTS trucker_npc_jobs;
DROP TABLE IF EXISTS trucker_npc_drivers;
DROP TABLE IF EXISTS trucker_loans;
DROP TABLE IF EXISTS trucker_adr_certs;
DROP TABLE IF EXISTS trucker_player_skills;
DROP TABLE IF EXISTS trucker_player_progression;
DROP TABLE IF EXISTS trucker_industry_ownership;
DROP TABLE IF EXISTS trucker_industry_state;
DROP TABLE IF EXISTS trucker_jobs;
DROP TABLE IF EXISTS trucker_company_vehicles;
DROP TABLE IF EXISTS trucker_company_members;
DROP TABLE IF EXISTS trucker_companies;

SET FOREIGN_KEY_CHECKS = 1;

-- =============================================
-- EMPRESAS
-- =============================================

CREATE TABLE `trucker_companies` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `trucker_company_members` (
    `citizenid`  VARCHAR(50) PRIMARY KEY,
    `company_id` VARCHAR(50) NOT NULL,
    `role`       ENUM('owner','manager','driver') DEFAULT 'driver',
    `joined_at`  DATETIME    DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`company_id`) REFERENCES `trucker_companies`(`id`) ON DELETE CASCADE,
    INDEX `idx_company_id` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `trucker_company_vehicles` (
    `plate`           VARCHAR(20) PRIMARY KEY,
    `company_id`      VARCHAR(50) NOT NULL,
    `model`           VARCHAR(50) NOT NULL,
    `vehicle_type`    VARCHAR(50) NOT NULL,
    `status`          ENUM('stored','out') DEFAULT 'stored',
    `added_at`        DATETIME    DEFAULT CURRENT_TIMESTAMP,
    `fuel_level`      FLOAT       DEFAULT 100.0,
    `has_gps_tracker` TINYINT(1)  NOT NULL DEFAULT 0,
    FOREIGN KEY (`company_id`) REFERENCES `trucker_companies`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================
-- JOBS DE ENTREGA
-- =============================================

CREATE TABLE `trucker_jobs` (
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
    `expires_at`         DATETIME      NOT NULL,
    `accepted_at`        DATETIME      NULL,
    `completed_at`       DATETIME      NULL,
    `created_at`         DATETIME      DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_status`         (`status`),
    INDEX `idx_assigned`       (`assigned_citizenid`),
    INDEX `idx_status_expires` (`status`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================
-- INDÚSTRIAS
-- =============================================

CREATE TABLE `trucker_industry_state` (
    `industry_id`          VARCHAR(50) NOT NULL,
    `item`                 VARCHAR(50) NOT NULL,
    `entry_type`           ENUM('production','consumption') NOT NULL,
    `current_price`        INT         NOT NULL,
    `current_stock`        INT         DEFAULT 0,
    `next_production_time` DATETIME    NULL,
    `last_npc_fill_at`     DATETIME    NULL DEFAULT NULL,
    `updated_at`           DATETIME    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`industry_id`, `item`, `entry_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `trucker_industry_ownership` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================
-- PROGRESSÃO DO JOGADOR
-- =============================================

CREATE TABLE `trucker_player_progression` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `trucker_player_skills` (
    `citizenid`   VARCHAR(50) NOT NULL,
    `skill_type`  ENUM('distance','valuable','fragile','speed') NOT NULL,
    `skill_level` TINYINT     DEFAULT 0,
    PRIMARY KEY (`citizenid`, `skill_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================
-- CERTIFICAÇÕES ADR
-- =============================================

CREATE TABLE `trucker_adr_certs` (
    `id`         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `citizenid`  VARCHAR(50) NOT NULL,
    `adr_type`   ENUM('flammable_liquid','flammable_gas','toxic','corrosive',
                     'explosive','environmental') NOT NULL,
    `expires_at` INT UNSIGNED NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_citizen_type` (`citizenid`, `adr_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================
-- SISTEMA FINANCEIRO
-- =============================================

CREATE TABLE `trucker_loans` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================
-- MOTORISTAS NPC
-- =============================================

CREATE TABLE `trucker_npc_drivers` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `trucker_npc_jobs` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================
-- REPO MAN
-- =============================================

CREATE TABLE `trucker_repo_orders` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================
-- INFRAÇÕES
-- =============================================

CREATE TABLE `trucker_infractions` (
    `id`              INT          AUTO_INCREMENT PRIMARY KEY,
    `citizenid`       VARCHAR(50)  NOT NULL,
    `job_id`          VARCHAR(50)  NULL,
    `infraction_type` ENUM('overload','no_manifest','expired_manifest',
                          'dangerous_cargo','illegal_seizure') NOT NULL,
    `reason`          TEXT         NOT NULL,
    `issued_by`       VARCHAR(100) NOT NULL,
    `created_at`      DATETIME     DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================
-- CONVOY / PARTIES
-- =============================================

CREATE TABLE `trucker_parties` (
    `id`         VARCHAR(36) PRIMARY KEY,
    `leader_cid` VARCHAR(50) NOT NULL,
    `members`    JSON        NOT NULL DEFAULT '[]',
    `max_size`   INT         NOT NULL DEFAULT 6,
    `status`     ENUM('forming','active','disbanded') NOT NULL DEFAULT 'forming',
    `created_at` DATETIME    NOT NULL DEFAULT NOW()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `trucker_convoy_jobs` (
    `id`           VARCHAR(36) PRIMARY KEY,
    `party_id`     VARCHAR(36) NOT NULL,
    `status`       ENUM('forming','active','completed','cancelled') NOT NULL DEFAULT 'forming',
    `bonus_mult`   FLOAT       NOT NULL DEFAULT 1.5,
    `active_count` INT         NOT NULL DEFAULT 0,
    `total_count`  INT         NOT NULL DEFAULT 0,
    `started_at`   DATETIME    NULL,
    `completed_at` DATETIME    NULL,
    FOREIGN KEY (`party_id`) REFERENCES `trucker_parties`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `trucker_convoy_members` (
    `convoy_id` VARCHAR(36) NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `job_id`    VARCHAR(50) NOT NULL,
    `status`    ENUM('pending','active','completed','abandoned') NOT NULL DEFAULT 'pending',
    PRIMARY KEY (`convoy_id`, `citizenid`),
    FOREIGN KEY (`convoy_id`) REFERENCES `trucker_convoy_jobs`(`id`),
    FOREIGN KEY (`job_id`)    REFERENCES `trucker_jobs`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `trucker_convoy_payments` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `trucker_rentals` (
    `citizenid`   VARCHAR(50) PRIMARY KEY,
    `plate`       VARCHAR(20) NOT NULL,
    `model`       VARCHAR(50) NOT NULL,
    `deposit`     INT         NOT NULL,
    `fee`         INT         NOT NULL,
    `refund_due`  INT         NULL DEFAULT NULL,
    `rented_at`   DATETIME    DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

