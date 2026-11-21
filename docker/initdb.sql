-- Role aplikasi WAJIB non-superuser & NOBYPASSRLS: superuser selalu melewati Row Level Security.
CREATE ROLE siagasos_app LOGIN PASSWORD 'siagasos_local' NOSUPERUSER NOBYPASSRLS;
CREATE DATABASE siagasos OWNER siagasos_app;
