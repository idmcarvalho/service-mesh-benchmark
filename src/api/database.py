"""Database models and connection management."""

from datetime import datetime
from enum import Enum
from typing import Optional

from sqlalchemy import (
    JSON,
    Column,
    DateTime,
    Float,
    Integer,
    String,
    Text,
    create_engine,
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import Session, sessionmaker

from src.api.config import settings

# Create database engine
# PostgreSQL configuration with connection pooling
engine = create_engine(
    settings.database_url,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,  # Verify connections before using
    pool_recycle=3600,   # Recycle connections after 1 hour
    echo=settings.debug,  # Log SQL statements in debug mode
)

# Create session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Create base class for models
Base = declarative_base()


class JobStatus(str, Enum):
    """Job status enumeration."""

    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class BenchmarkJob(Base):
    """Benchmark job model for tracking test executions."""

    __tablename__ = "benchmark_jobs"

    id = Column(String, primary_key=True, index=True)
    test_type = Column(String, nullable=False, index=True)
    mesh_type = Column(String, nullable=False, index=True)
    status = Column(String, nullable=False, default=JobStatus.PENDING, index=True)

    # Configuration
    duration = Column(Integer, nullable=False)
    concurrent_connections = Column(Integer, nullable=False)
    namespace = Column(String, nullable=False)

    # Results
    throughput = Column(Float, nullable=True)
    latency_p50 = Column(Float, nullable=True)
    latency_p95 = Column(Float, nullable=True)
    latency_p99 = Column(Float, nullable=True)
    error_rate = Column(Float, nullable=True)

    # Metadata
    results_file = Column(String, nullable=True)
    error_message = Column(Text, nullable=True)
    metadata = Column(JSON, nullable=True)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)

    def __repr__(self) -> str:
        """String representation of job."""
        return f"<BenchmarkJob {self.id} ({self.test_type}/{self.mesh_type}): {self.status}>"


class EBPFProbeJob(Base):
    """eBPF probe job model for tracking probe executions."""

    __tablename__ = "ebpf_probe_jobs"

    id = Column(String, primary_key=True, index=True)
    probe_type = Column(String, nullable=False, index=True)
    target_namespace = Column(String, nullable=False)
    status = Column(String, nullable=False, default=JobStatus.PENDING, index=True)

    # Configuration
    duration = Column(Integer, nullable=False)

    # Results
    results_file = Column(String, nullable=True)
    error_message = Column(Text, nullable=True)
    metadata = Column(JSON, nullable=True)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)

    def __repr__(self) -> str:
        """String representation of probe job."""
        return f"<EBPFProbeJob {self.id} ({self.probe_type}): {self.status}>"


class Report(Base):
    """Report model for tracking generated reports."""

    __tablename__ = "reports"

    id = Column(String, primary_key=True, index=True)
    report_type = Column(String, nullable=False)
    format = Column(String, nullable=False)

    # Configuration
    job_ids = Column(JSON, nullable=True)  # List of benchmark job IDs included

    # Output
    file_path = Column(String, nullable=False)
    file_size_bytes = Column(Integer, nullable=True)

    # Metadata
    metadata = Column(JSON, nullable=True)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    def __repr__(self) -> str:
        """String representation of report."""
        return f"<Report {self.id} ({self.report_type}/{self.format})>"


def get_db() -> Session:
    """Get database session.

    Yields:
        Database session
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """Initialize database by creating all tables."""
    Base.metadata.create_all(bind=engine)


def cleanup_old_jobs(days: int = 30) -> int:
    """Clean up old completed jobs.

    Args:
        days: Number of days to retain jobs

    Returns:
        Number of jobs deleted
    """
    from datetime import timedelta

    cutoff_date = datetime.utcnow() - timedelta(days=days)

    db = SessionLocal()
    try:
        deleted_benchmark = (
            db.query(BenchmarkJob)
            .filter(
                BenchmarkJob.completed_at < cutoff_date,
                BenchmarkJob.status.in_([JobStatus.COMPLETED, JobStatus.FAILED]),
            )
            .delete()
        )

        deleted_ebpf = (
            db.query(EBPFProbeJob)
            .filter(
                EBPFProbeJob.completed_at < cutoff_date,
                EBPFProbeJob.status.in_([JobStatus.COMPLETED, JobStatus.FAILED]),
            )
            .delete()
        )

        db.commit()
        return deleted_benchmark + deleted_ebpf
    finally:
        db.close()
