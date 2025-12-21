ALTER TABLE investigations 
    ADD COLUMN dataset_search TSVECTOR;

CREATE OR REPLACE FUNCTION extract_searchable_text(turtle_text TEXT) 
RETURNS TEXT AS $$
DECLARE
    result TEXT := '';
BEGIN
    -- Estrai le URI (es. <http://example.org/ns#E55_Type>)
    result := result || ' ' || regexp_replace(turtle_text, '<([^>]+)>', '\1', 'g');

    -- Estrai i letterali (es. "E55_Type")
    result := result || ' ' || regexp_replace(turtle_text, '"([^"]+)"', '\1', 'g');

    RETURN result;
END;
$$ LANGUAGE plpgsql;

UPDATE investigations 
    SET dataset_search = to_tsvector('english', extract_searchable_text(dataset));

CREATE OR REPLACE FUNCTION update_investigations_search() 
RETURNS TRIGGER AS $$
BEGIN
    NEW.dataset_search := to_tsvector('english', COALESCE(extract_searchable_text(NEW.dataset), ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_investigations_search_update
BEFORE INSERT OR UPDATE ON investigations
FOR EACH ROW EXECUTE FUNCTION update_investigations_search();

CREATE INDEX idx_investigations_search ON investigations USING GIN(dataset_search);

ALTER TABLE investigations ADD column id BIGINT NOT NULL default 0;
