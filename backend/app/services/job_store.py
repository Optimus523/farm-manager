import json
from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel

from app.core.database import SupabaseRepository


class JobStatus(str, Enum):
    """Job status enum."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class JobRecord(BaseModel):
    """Job record model."""
    id: str
    job_type: str
    status: JobStatus
    started_at: datetime
    completed_at: datetime | None = None
    result: dict[str, Any] | None = None
    error: str | None = None
    metadata: dict[str, Any] | None = None


class JobStore:
    """
    Persistent job storage using Supabase.
    
    Uses the 'pipeline_jobs' table to track background jobs.
    Falls back to in-memory storage if table doesn't exist.
    """
    
    TABLE_NAME = "pipeline_jobs"
    
    def __init__(self):
        self.repo = SupabaseRepository()
        self._fallback_store: dict[str, dict] = {}
        self._use_db = True
    
    async def _ensure_table(self) -> bool:
        """Check if table exists, fall back to memory if not."""
        try:
            self.repo.client.table(self.TABLE_NAME).select("id").limit(1).execute()
            return True
        except Exception:
            self._use_db = False
            return False
    
    async def create_job(
        self,
        job_id: str,
        job_type: str,
        metadata: dict[str, Any] | None = None,
    ) -> JobRecord:
        """Create a new job record."""
        now = datetime.now(datetime.now.utc)
        
        job = JobRecord(
            id=job_id,
            job_type=job_type,
            status=JobStatus.PENDING,
            started_at=now,
            metadata=metadata,
        )
        
        if self._use_db:
            try:
                self.repo.client.table(self.TABLE_NAME).insert({
                    "id": job_id,
                    "job_type": job_type,
                    "status": job.status.value,
                    "started_at": now.isoformat(),
                    "metadata": json.dumps(metadata) if metadata else None,
                }).execute()
            except Exception:
                # Fall back to memory
                self._use_db = False
        
        if not self._use_db:
            self._fallback_store[job_id] = job.model_dump()
        
        return job
    
    async def update_job(
        self,
        job_id: str,
        status: JobStatus,
        result: dict[str, Any] | None = None,
        error: str | None = None,
    ) -> JobRecord | None:
        """Update job status and results."""
        now = datetime.timezone.utc
        
        update_data = {
            "status": status.value,
            "completed_at": now.isoformat() if status in (JobStatus.COMPLETED, JobStatus.FAILED) else None,
        }
        
        if result:
            update_data["result"] = json.dumps(result)
        if error:
            update_data["error"] = error
        
        if self._use_db:
            try:
                response = self.repo.client.table(self.TABLE_NAME).update(
                    update_data
                ).eq("id", job_id).execute()
                
                if response.data:
                    data = response.data[0]
                    return JobRecord(
                        id=data["id"],
                        job_type=data["job_type"],
                        status=JobStatus(data["status"]),
                        started_at=datetime.fromisoformat(data["started_at"]),
                        completed_at=datetime.fromisoformat(data["completed_at"]) if data.get("completed_at") else None,
                        result=json.loads(data["result"]) if data.get("result") else None,
                        error=data.get("error"),
                        metadata=json.loads(data["metadata"]) if data.get("metadata") else None,
                    )
            except Exception:
                self._use_db = False
        
        if not self._use_db and job_id in self._fallback_store:
            self._fallback_store[job_id].update({
                "status": status.value,
                "completed_at": now.isoformat() if status in (JobStatus.COMPLETED, JobStatus.FAILED) else None,
                "result": result,
                "error": error,
            })
            return JobRecord(**self._fallback_store[job_id])
        
        return None
    
    async def get_job(self, job_id: str) -> JobRecord | None:
        """Get a job by ID."""
        if self._use_db:
            try:
                response = self.repo.client.table(self.TABLE_NAME).select(
                    "*"
                ).eq("id", job_id).maybe_single().execute()
                
                if response.data:
                    data = response.data
                    return JobRecord(
                        id=data["id"],
                        job_type=data["job_type"],
                        status=JobStatus(data["status"]),
                        started_at=datetime.fromisoformat(data["started_at"]),
                        completed_at=datetime.fromisoformat(data["completed_at"]) if data.get("completed_at") else None,
                        result=json.loads(data["result"]) if data.get("result") else None,
                        error=data.get("error"),
                        metadata=json.loads(data["metadata"]) if data.get("metadata") else None,
                    )
            except Exception:
                self._use_db = False
        
        if not self._use_db and job_id in self._fallback_store:
            return JobRecord(**self._fallback_store[job_id])
        
        return None
    
    async def list_jobs(
        self,
        job_type: str | None = None,
        status: JobStatus | None = None,
        limit: int = 50,
    ) -> list[JobRecord]:
        """List jobs with optional filters."""
        if self._use_db:
            try:
                query = self.repo.client.table(self.TABLE_NAME).select("*")
                
                if job_type:
                    query = query.eq("job_type", job_type)
                if status:
                    query = query.eq("status", status.value)
                
                response = query.order("started_at", desc=True).limit(limit).execute()
                
                return [
                    JobRecord(
                        id=data["id"],
                        job_type=data["job_type"],
                        status=JobStatus(data["status"]),
                        started_at=datetime.fromisoformat(data["started_at"]),
                        completed_at=datetime.fromisoformat(data["completed_at"]) if data.get("completed_at") else None,
                        result=json.loads(data["result"]) if data.get("result") else None,
                        error=data.get("error"),
                        metadata=json.loads(data["metadata"]) if data.get("metadata") else None,
                    )
                    for data in response.data
                ]
            except Exception:
                self._use_db = False
        
        # Fallback to memory
        jobs = list(self._fallback_store.values())
        
        if job_type:
            jobs = [j for j in jobs if j.get("job_type") == job_type]
        if status:
            jobs = [j for j in jobs if j.get("status") == status.value]
        
        jobs.sort(key=lambda x: x.get("started_at", ""), reverse=True)
        
        return [JobRecord(**j) for j in jobs[:limit]]


# Singleton instance
_job_store: JobStore | None = None


def get_job_store() -> JobStore:
    """Get singleton JobStore instance."""
    global _job_store
    if _job_store is None:
        _job_store = JobStore()
    return _job_store
