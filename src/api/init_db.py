#!/usr/bin/env python3
"""Database initialization script.

Creates all tables and sets up the database schema.
"""

import sys
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.api.database import Base, engine, init_db
from src.api.settings import settings


def main():
    """Initialize the database."""
    print(f"Initializing database: {settings.database_url}")

    try:
        # Create all tables
        Base.metadata.create_all(bind=engine)
        print("✓ Database tables created successfully")

        # Verify tables exist
        from sqlalchemy import inspect
        inspector = inspect(engine)
        tables = inspector.get_table_names()

        print(f"\n✓ Created {len(tables)} tables:")
        for table in tables:
            print(f"  - {table}")

    except Exception as e:
        print(f"✗ Error initializing database: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
