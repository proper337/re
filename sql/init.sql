#
# ON UPDATE CASCADE ON DELETE RESTRICT
# http://stackoverflow.com/questions/1027656/what-is-mysqls-default-on-delete-behavior
#

create database if not exists re;

use re;

create table if not exists state (
       id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
       PRIMARY KEY(id),
       state            VARCHAR(100) NOT NULL
       ) ENGINE=INNODB;

create table if not exists city (
       id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
       PRIMARY KEY(id),
       city             VARCHAR(100) NOT NULL, 
       dist             DECIMAL(10,2) NOT NULL # distance from primary city (metro-area)
       ) ENGINE=INNODB;

create table if not exists state_city (
       state_id         INT UNSIGNED NOT NULL,
       city_id          INT UNSIGNED NOT NULL,
       FOREIGN KEY (state_id) REFERENCES state(id),
       FOREIGN KEY (city_id) REFERENCES city(id),
       UNIQUE(state_id,city_id)
       ) ENGINE=INNODB;

create table if not exists mls (
       mls              VARCHAR(64) NOT NULL,
       PRIMARY KEY(mls),
       state_id         INT UNSIGNED NOT NULL,
       city_id          INT UNSIGNED NOT NULL,
       added            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
       seen             TIMESTAMP,
       FOREIGN KEY (state_id) REFERENCES state(id),
       FOREIGN KEY (city_id) REFERENCES city(id)
       ) ENGINE=INNODB;

create table if not exists mls_status_history (
       mls              VARCHAR(64) NOT NULL, 
       status           VARCHAR(128),
       added            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
       PRIMARY KEY(mls,status),
       FOREIGN KEY (mls) REFERENCES mls(mls)
       ) ENGINE=INNODB;

create table if not exists price_history (
       mls              VARCHAR(64) NOT NULL,
       added            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
       status           VARCHAR(128),
       address          VARCHAR(128),
       price            DECIMAL(10,2),
       offered          DECIMAL(10,2),
       sqft             DECIMAL(10,2),
       ppsqft           DECIMAL(10,2),
       beds             DECIMAL(10,2),
       baths            DECIMAL(10,2),
       lot              DECIMAL(10,2),
       built            SMALLINT,
       hoa              DECIMAL(10,2),
       dos              SMALLINT,
       url              VARCHAR(1024),
       presented_by     VARCHAR(1024),
       brokered_by      VARCHAR(1024),
       features         VARCHAR(2048),
       zip              INT UNSIGNED,
       hashdump         VARCHAR(40000),
       UNIQUE(mls,price),
       FOREIGN KEY (mls) REFERENCES mls(mls)
       ) ENGINE=INNODB;

