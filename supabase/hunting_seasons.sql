-- ============================================================================
-- Сроки охоты — справочник (публичный, без входа).
-- Выполняйте в Supabase → SQL Editor.
-- ============================================================================

-- 1. Таблица
create table if not exists public.hunting_seasons (
  id bigint generated always as identity primary key,
  region_id text not null,
  region_name text not null,
  resource text not null,
  season text not null,
  species text not null,
  open_date text,
  close_date text,
  restrictions text,
  zone text,
  date_rule text,
  close_rule text,
  created_at timestamptz not null default now()
);

-- 2. Разрешаем чтение всем (в т.ч. анонимам) — справочник работает без входа.
alter table public.hunting_seasons enable row level security;

drop policy if exists "public_read" on public.hunting_seasons;
create policy "public_read"
  on public.hunting_seasons
  for select
  using (true);

-- 3. Запрещаем запись из клиента (только админ/сервис вносит данные).
drop policy if exists "no_client_write" on public.hunting_seasons;
create policy "no_client_write"
  on public.hunting_seasons
  for all
  using (false)
  with check (false);

-- 4. Индекс для быстрого поиска.
create index if not exists idx_hunting_seasons_region on public.hunting_seasons (region_id);
create index if not exists idx_hunting_seasons_species on public.hunting_seasons (species);

-- 5. Данные
truncate table public.hunting_seasons restart identity;
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Весна', 'Пернатая дичь (все виды)', '01.03', '16.06', 'Запрет на проведение любительской и спортивной охоты на пернатую дичь в весенний период на территории Краснодарского края', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Весна', 'Косуля европейская: взрослые самцы', '20.05', '20.06', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Медведи', 'Весна', 'Медведь бурый', '21.03', '30.05', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Лето', 'Перепел, голуби и горлицы, самец фазана', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Лето', 'Вальдшнеп', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Лето', 'Перепел, голуби и горлицы, самец фазана', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Лето', 'Вальдшнеп', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Боровая дичь', 'Лето', 'Вальдшнеп', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Лето', 'Кабан: все половозрастные группы', '01.06', '28.02', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Лето', 'Туры: все половозрастные группы', '01.08', '30.11', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Лето', 'Косуля европейская: взрослые самцы', '20.05', '20.06', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Лето', 'Косуля европейская: взрослые самцы', '15.07', '15.08', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Лето', 'Олень благородный: взрослые самцы с неокостеневшими рогами (пантами)', '01.06', '15.07', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Лето', 'Крот', '01.06', '25.10', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Лето', 'Сурок степной, суслик малый, хомяки', '15.06', '30.09', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Степная и полевая дичь', 'Лето', 'Перепел, голуби и горлицы, самец фазана', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Степная и полевая дичь', 'Лето', 'Перепел, голуби и горлицы, самец фазана', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Осень', 'Перепел, голуби и горлицы, самец фазана', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Осень', 'Вальдшнеп', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Осень', 'Лысуха, гуси, утки', '26.09', '20.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Осень', 'Дупель, бекасы, гаршнеп, травник, чибис, тулес, улиты, мородунка, камнешарка', '01.09', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Осень', 'Коростель', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Осень', 'Перепел, голуби и горлицы, самец фазана', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Осень', 'Вальдшнеп', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Осень', 'Серая ворона', '15.08', '20.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Осень', 'Баклан большой', '01.09', '20.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Болотно-луговая дичь', 'Осень', 'Дупель, бекасы, гаршнеп, травник, чибис, тулес, улиты, мородунка, камнешарка', '01.09', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Болотно-луговая дичь', 'Осень', 'Коростель', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Боровая дичь', 'Осень', 'Вальдшнеп', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Боровая дичь', 'Осень', 'Вальдшнеп', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Водоплавающая дичь', 'Осень', 'Лысуха, гуси, утки', '26.09', '20.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Осень', 'Кабан: все половозрастные группы', '01.06', '28.02', NULL, 'Все');

INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Осень', 'Туры: все половозрастные группы', '01.08', '30.11', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Осень', 'Косуля европейская: все половозрастные группы', '01.10', '10.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Осень', 'Олень благородный: все половозрастные группы', '01.10', '10.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Осень', 'Олень благородный: взрослые самцы', '01.09', '30.09', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Медведи', 'Осень', 'Медведь бурый', '01.10', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Осень', 'Лисица, енотовидная собака, заяц русак', '15.09', '28.02', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Осень', 'Волк, шакал', '01.08', '31.03', 'На территории общедоступных охотничьих угодий Краснодарского края применение петель запрещено. На территории закрепленных охотничьих угодий Краснодарского края разрешен отлов волка и шакала петлями, изготовленными из многожильного металлического троса диаметром не более 4 миллиметров и общей длиной троса не более 150 сантиметров, в целях регулирования их численности, таким способом, который исключает причинение вреда другим объектам животного мира, за исключением территорий муниципальных образований город-курорт Анапа, город-курорт Геленджик, город Горячий Ключ, город Новороссийск, Абинский район, Апшеронский район, Белореченский район, Гулькевичский район, Кавказский район, Крымский район, Лабинский район, Мостовский район, Новокубанский район, Отрадненский район, Северский район, Тбилисский район, Туапсинский район.', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Осень', 'Барсук', '15.08', '31.10', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Осень', 'Водяная полевка, Ондатра', '01.11', '28.02', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Осень', 'Крот', '01.06', '25.10', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Осень', 'Сурок степной, суслик малый, хомяки', '15.06', '30.09', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Осень', 'Белки, енот-полоскун, куница (лесная, каменная), ласка, хорь (лесной, степной)', '15.10', '11.02', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Степная и полевая дичь', 'Осень', 'Перепел, голуби и горлицы, самец фазана', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Степная и полевая дичь', 'Осень', 'Перепел, голуби и горлицы, самец фазана', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Зима', 'Перепел, голуби и горлицы, самец фазана', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Зима', 'Вальдшнеп', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Зима', 'Лысуха, гуси, утки', '26.09', '20.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Зима', 'Дупель, бекасы, гаршнеп, травник, чибис, тулес, улиты, мородунка, камнешарка', '01.09', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Зима', 'Коростель', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Зима', 'Перепел, голуби и горлицы, самец фазана', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Зима', 'Вальдшнеп', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Зима', 'Серая ворона', '15.08', '20.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пернатая дичь', 'Зима', 'Баклан большой', '01.09', '20.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Болотно-луговая дичь', 'Зима', 'Дупель, бекасы, гаршнеп, травник, чибис, тулес, улиты, мородунка, камнешарка', '01.09', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Болотно-луговая дичь', 'Зима', 'Коростель', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Боровая дичь', 'Зима', 'Вальдшнеп', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Боровая дичь', 'Зима', 'Вальдшнеп', '15.08', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Водоплавающая дичь', 'Зима', 'Лысуха, гуси, утки', '26.09', '20.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Зима', 'Кабан: все половозрастные группы', '01.06', '28.02', NULL, 'Все');

INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Зима', 'Косуля европейская: все половозрастные группы', '01.10', '10.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Копытные животные', 'Зима', 'Олень благородный: все половозрастные группы', '01.10', '10.01', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Медведи', 'Зима', 'Медведь бурый', '01.10', '31.12', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Зима', 'Лисица, енотовидная собака, заяц русак', '15.09', '28.02', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Зима', 'Волк, шакал', '01.08', '31.03', 'На территории общедоступных охотничьих угодий Краснодарского края применение петель запрещено. На территории закрепленных охотничьих угодий Краснодарского края разрешен отлов волка и шакала петлями, изготовленными из многожильного металлического троса диаметром не более 4 миллиметров и общей длиной троса не более 150 сантиметров, в целях регулирования их численности, таким способом, который исключает причинение вреда другим объектам животного мира, за исключением территорий муниципальных образований город-курорт Анапа, город-курорт Геленджик, город Горячий Ключ, город Новороссийск, Абинский район, Апшеронский район, Белореченский район, Гулькевичский район, Кавказский район, Крымский район, Лабинский район, Мостовский район, Новокубанский район, Отрадненский район, Северский район, Тбилисский район, Туапсинский район.', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Зима', 'Водяная полевка, Ондатра', '01.11', '28.02', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Пушные животные', 'Зима', 'Белки, енот-полоскун, куница (лесная, каменная), ласка, хорь (лесной, степной)', '15.10', '11.02', NULL, 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Степная и полевая дичь', 'Зима', 'Перепел, голуби и горлицы, самец фазана', '15.08', '16.01', 'Только с островными и континентальными легавыми собаками, ретриверами, спаниелями, имеющими справку или свидетельство о происхождении', 'Все');
INSERT INTO hunting_seasons (region_id, region_name, resource, season, species, open_date, close_date, restrictions, zone) VALUES ('krasnodar', 'Краснодарский край', 'Степная и полевая дичь', 'Зима', 'Перепел, голуби и горлицы, самец фазана', '15.08', '31.12', NULL, 'Все');

-- 6. Плавающие даты открытия сезона (правило вместо фиксированной даты).
--    Формат: 'N-wd:MM' — N-й день недели месяца (mon..sun). Клиент вычисляет
--    конкретную дату для текущего года. В open_date остаётся дата-подсказка
--    (обычно верная для текущего сезона).
-- 6.1 Водоплавающая дичь — с четвёртой субботы сентября.
update public.hunting_seasons set date_rule = '4-sat:09'
  where region_id = 'krasnodar' and species = 'Лысуха, гуси, утки';
-- 6.2 Степная, полевая и боровая дичь — с третьей субботы августа.
update public.hunting_seasons set date_rule = '3-sat:08'
  where region_id = 'krasnodar'
    and open_date = '15.08'
    and resource in ('Пернатая дичь', 'Степная и полевая дичь', 'Боровая дичь')
    and species in ('Перепел, голуби и горлицы, самец фазана', 'Вальдшнеп');