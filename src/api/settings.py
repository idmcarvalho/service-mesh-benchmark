"""API settings and configuration management."""

import os
from pathlib import Path
from typing import List, Optional

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Database configuration (OPTIONAL - uses in-memory by default)
    database_url: Optional[str] = Field(
        default=None,
        description="Database connection URL (PostgreSQL) - Optional, uses in-memory state if not provided",
    )

    database_enabled: bool = Field(
        default=False,
        description="Enable database persistence (requires database_url)",
    )

    # Redis configuration (OPTIONAL - not required for basic operation)
    redis_url: Optional[str] = Field(
        default=None,
        description="Redis connection URL for job queue - Optional",
    )

    redis_enabled: bool = Field(
        default=False,
        description="Enable Redis for job queuing (requires redis_url)",
    )

    # Job persistence configuration
    persistence_enabled: bool = Field(
        default=True,
        description="Enable JSON file-based job persistence (lightweight alternative to database)",
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

    @property
    def cors_origins(self) -> List[str]:
        """Parse allowed origins into a list."""
        return [origin.strip() for origin in self.allowed_origins.split(",") if origin.strip()]

    # Security Configuration
    secret_key: str = Field(
        default="changeme-in-production-use-secrets-manager",
        description="Secret key for JWT and session signing",
    )

    access_token_expire_minutes: int = Field(
        default=30,
        description="Access token expiration time in minutes",
    )

    # Rate Limiting
    rate_limit_enabled: bool = Field(
        default=True,
        description="Enable rate limiting",
    )

    rate_limit_per_minute: int = Field(
        default=60,
        description="Maximum requests per minute per client",
    )

    # Security Headers
    security_headers_enabled: bool = Field(
        default=True,
        description="Enable security headers middleware",
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

    # Logging
    log_level: str = Field(
        default="INFO",
        description="Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)",
    )

    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, v: str) -> str:
        """Validate log level."""
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if v.upper() not in valid_levels:
            raise ValueError(f"Log level must be one of {valid_levels}")
        return v.upper()

    # Production Security Warnings
    @property
    def is_production(self) -> bool:
        """Check if running in production mode."""
        return not self.debug

    def validate_production_config(self) -> List[str]:
        """Validate production configuration and return warnings."""
        warnings = []

        if self.is_production:
            if self.secret_key == "changeme-in-production-use-secrets-manager":
                warnings.append(
                    "SECRET_KEY is using default value. "
                    "Please set a secure random key in production!"
                )

            if "localhost" in self.allowed_origins:
                warnings.append(
                    "ALLOWED_ORIGINS contains localhost. "
                    "Update to include only production domains!"
                )

            if not self.security_headers_enabled:
                warnings.append(
                    "Security headers are disabled. "
                    "Enable SECURITY_HEADERS_ENABLED=true in production!"
                )

        return warnings

    class Config:
        """Pydantic settings configuration."""

        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


# Global settings instance
settings = Settings()
