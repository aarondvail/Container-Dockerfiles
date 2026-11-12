-- Run once against your existing Postgres as a superuser, e.g.:
--   docker exec -i <your-postgres-container> psql -U postgres < postgres-setup.sql
-- Your Postgres image must include PostGIS (see notes).
CREATE ROLE <DBUser> WITH LOGIN PASSWORD '<DBPassWord>';   -- match POSTGRES_PASSWORD in .env
CREATE DATABASE <DBUser> OWNER <DBUser>;
\c <DBUser>
CREATE EXTENSION IF NOT EXISTS postgis;
GRANT ALL ON SCHEMA public TO <DBUser>;
