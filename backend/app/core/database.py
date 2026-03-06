from functools import lru_cache

from supabase import Client, create_client

from app.core.config import get_settings


@lru_cache
def get_supabase_client() -> Client:
    settings = get_settings()
    return create_client(settings.supabase_url, settings.supabase_key)


@lru_cache
def get_supabase_service_client() -> Client:
    settings = get_settings()
    if not settings.supabase_service_key:
        raise ValueError("SUPABASE_SERVICE_KEY is required for service operations")
    return create_client(settings.supabase_url, settings.supabase_service_key)


class SupabaseRepository: 
    def __init__(self, client: Client | None = None, use_service_role: bool = True):
        if client:
            self.client = client
        elif use_service_role:
            self.client = get_supabase_service_client()
        else:
            self.client = get_supabase_client()

    async def fetch_all(self, table: str, filters: dict | None = None) -> list[dict]:
        query = self.client.table(table).select("*")
        if filters:
            for key, value in filters.items():
                query = query.eq(key, value)
        response = query.execute()
        return response.data

    async def fetch_by_id(self, table: str, id: str) -> dict | None:
        response = self.client.table(table).select("*").eq("id", id).maybe_single().execute()
        return response.data

    async def fetch_by_farm(self, table: str, farm_id: str) -> list[dict]:
        response = self.client.table(table).select("*").eq("farm_id", farm_id).execute()
        return response.data
