CREATE OR REPLACE FUNCTION get_json() 
RETURNS trigger AS $$
--view (occurrence_id text, specimen_id int4, json_column json) AS $BODY$
BEGIN 
 IF (TG_OP = 'INSERT')  THEN 
   DROP table IF EXISTS json_store_table;
    create table json_store_table as 
select occurrence_id, specimen_id,  (select to_json(array_agg(row_to_json(t)))
from (
  select occurrence_id as occurrence_id,
    (
      select array_to_json(array_agg(row_to_json(d)))
      from (
        select
        jsonb_build_object('specimen_id', specimen_id, 'campo', campo, 'comentario', comentario, 'created', created, 'created_user', created_user, 'id_coment', id_comments) as registros
        from store_comments as t1
        where t1.occurrence_id = t2.occurrence_id 
        group by specimen_id, campo, comentario, created, created_user, id_comments
        order by created desc limit 1
      ) d
    ) as observaciones
  from store_comments as t2
  where t3.occurrence_id = t2.occurrence_id
  group by occurrence_id limit 1
) t)  as json_column from store_comments  as t3 group by occurrence_id, specimen_id, created order by created desc limit 1;

END IF;

IF to_regclass('produccion.json_store_table') IS NOT NULL THEN ALTER TABLE json_store_table ADD COLUMN json_column_w TEXT, ADD COLUMN elements TEXT;

END IF;


IF EXISTS (SELECT json_column_w from json_store_table where json_column_w IS NULL) THEN  UPDATE json_store_table SET json_column_w = btrim(json_column::TEXT, '[]');
 END IF;
 
 IF EXISTS (SELECT json_column_w, elements from json_store_table where json_column_w IS NOT NULL AND elements IS NULL) THEN  UPDATE json_store_table SET elements = json_array_elements_text(json_column_w::json->'observaciones');
 END IF;
 

IF EXISTS (SELECT json_column_w, elements from json_store_table where json_column_w IS NOT NULL AND elements IS NOT NULL) then drop table if exists json_to_update_table ; create table json_to_update_table as select json_store_table.occurrence_id, json_store_table.specimen_id,  json_store, elements, regexp_replace(json_store::text, 'observaciones\": \[', 'observaciones": [' || elements||', ') as json_ready
from biodiversity inner join json_store_table 
on biodiversity.occurrence_id = json_store_table.occurrence_id
and biodiversity.specimen_id = json_store_table.specimen_id;

END IF;

IF to_regclass('produccion.json_to_update_table') IS NOT NULL THEN --ALTER TABLE json_store_table ADD COLUMN json_column_w TEXT, ADD COLUMN elements TEXT;
UPDATE biodiversity set json_store = json_ready::json from json_to_update_table
where biodiversity.occurrence_id = json_to_update_table.occurrence_id
and biodiversity.specimen_id = json_to_update_table.specimen_id;
END IF;
  RETURN NULL;
END$$
  LANGUAGE plpgsql VOLATILE;
	
	CREATE TRIGGER update_json
AFTER INSERT 
ON store_comments 
FOR EACH ROW EXECUTE PROCEDURE get_json();
