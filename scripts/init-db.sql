-- Initialize Service Mesh Benchmark Database
-- This script is run automatically by PostgreSQL on first startup

-- Ensure we're using the correct database
\c service_mesh_benchmark;

-- Create extensions if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Grant necessary permissions
GRANT ALL PRIVILEGES ON DATABASE service_mesh_benchmark TO benchmark;
GRANT ALL PRIVILEGES ON SCHEMA public TO benchmark;

-- Create indexes for performance (will be created by SQLAlchemy, but explicit is better)
-- Tables will be created by SQLAlchemy migrations

-- Print completion message
\echo 'Database initialization complete!';
