from typing import Dict, Optional
from app.core.database import get_supabase_client
from app.core.config import get_settings
from google import genai
from app.services.embedding import EmbeddingService


settings = get_settings()

class MemoryService:
    def __init__(self, embedding):
        self.client = genai.Client(api_key=settings.gemini_api_key)
        self.supabase_client = get_supabase_client()
        self.embedding = embedding
    
    async def add_memory(
        self, 
        container_tag: str,
        content: str,
        memory_type: str = "fact",
        category: Optional[str] = None,
        expires_at: Optional[str] = None,
        metadata: Dict = {},
        importance: float = 0.5,
        source: str = "user"
    ):
        
        text_embedding = await self.embedding.embed_text(content)
         
        result = self.supabase_client.rpc('add_memory', {
            'p_container_tag': container_tag,
            'p_content': content,
            'p_embedding': text_embedding,
            'p_container_type': 'general',
            'p_metadata': metadata,
            'p_memory_type': memory_type,
            'p_category': category,
            'p_importance': importance,
            'p_tags': [],
            'p_expires_at': expires_at,
            'p_source': source
        }).execute()
        
        return result.data
    
    async def search(
        self, 
        query: str, 
        limit: int = 10, 
        container_tag: Optional[str] = None,
        memory_type: Optional[str] = None,
        threshold: float = 0.7,
    ):
        
        query_embedding = await self.embedding.embed_query(query)
        
        if container_tag is None:
            return []
            
        result = self.supabase_client.rpc('search_memories', {
            'query_embedding': query_embedding,
            'p_container_tag': container_tag,
            'match_threshold': threshold,
            'match_count': limit,
            'p_memory_type': memory_type,
            'p_category': None,
            'include_expired': False
        }).execute()
        
        return result.data if result.data else []

memory = None


def get_memory_service():
    global memory
    settings = get_settings()
    embedding = EmbeddingService(api_key=settings.gemini_api_key)
    if memory is None:
        memory = MemoryService(embedding=embedding)
    return memory
