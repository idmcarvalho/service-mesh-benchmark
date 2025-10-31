"""API settings and configuration management."""

import os
from pathlib import Path
from typing import Optional

from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Database configuration
    database_url: str = Field(
        default="postgresql://benchmark:benchmark@localhost:5432/service_mesh_benchmark",
        description="Database connection URL (PostgreSQL)",
    )

    # API Configuration
    debug: bool = Field(
        default=False,
        description="Enable debug mode",
    )

    api_host: str = Field(
        default="0.0.0.0",
        description="API host to bind to",
    )

    api_port: int = Field(
        default=8000,
        description="API port to bind to",
    )

    # CORS Configuration
    allowed_origins: str = Field(
        default="http://localhost:3000,http://localhost:8000,http://localhost:8080",
        description="Comma-separated list of allowed CORS origins",
    )

    # Results directory
    results_dir: Optional[Path] = Field(
        default=None,
        description="Directory for storing benchmark results",
    )

    # eBPF probe configuration
    ebpf_probe_dir: Optional[Path] = Field(
        default=None,
        description="Directory containing eBPF probe binaries",
    )

    class Config:
        """Pydantic settings configuration."""

        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


# Global settings instance
settings = Settings()
