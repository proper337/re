use re;

insert into state(state) values('CA');
select @state_id := last_insert_id();

insert into city(city,dist) values('Sacramento',0);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('North Sacramento',2.6);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Fruitridge',2.8);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Bryte',4.1);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Broderick',4.1);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Walsh Station',5.0);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('West Sacramento',5.0);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Mcclellan',7.2);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Southport',7.3);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('North Highlands',7.6);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Rio Linda',7.9);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Carmichael',8.3);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('El Macero',9.4);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Mather',9.9);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Elverta',11.0);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Gold River',11.1);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Nimbus',11.1);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Antelope',11.5);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Rancho Cordova',11.5);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Elk Grove',12.6);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Fair Oaks',12.8);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Citrus Heights',13.1);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Davis',13.5);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Clarksburg',13.6);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Hood',14.5);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());

insert into city(city,dist) values('Orangevale',15.3);
insert into state_city(state_id,city_id) values(@state_id, last_insert_id());
