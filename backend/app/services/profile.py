from app.services.embedding import EmbeddingService
from typing import Optional, Dict
from app.core.database import get_supabase_client

class ProfileService:
    def __init__(self, embedding_service: EmbeddingService):
        self.supabase_client = get_supabase_client()
        self.embedding = embedding_service
    
    async def get_profile(
        self, 
        container_tag: str, 
        query: Optional[str], 
        include_search: bool
        ):
        query_embedding = None
        if query and include_search:
            query_embedding = await self.embedding.embed_query(query)
        result = self.supabase_client.rpc("get_memory_profile", {
            'p_container_tag': container_tag,
            'p_query_embedding': query_embedding,
            'p_query_text': query,
            'p_include_search': include_search,
            'p_search_limit': 5
        }).execute()
        
        return result.data
    
    def build_context_prompt(self, profile: Dict):
        static = profile.get("profile", {}).get("static", [])
        dynamic = profile.get("profile", {}).get("dynamic", [])
        search_results = profile.get("profile", [])
        
        context_parts = []
        
        if static:
            context_parts.append("## User Profile (Always Relevant")
            for fact in static[:10]:
                context_parts.append(f"- {fact}")
            
        if dynamic:
            context_parts.append("\n## Recent Context")
            for episode in dynamic[:5]:
                context_parts.append(f"- {episode}")
        
        if search_results:
            context_parts.append("\n## Relevant Memories")
            for mem in search_results[:5]:
                context_parts.append(f"- {mem.get('content', '')}")
        return "\n".join(context_parts)