from typing import Optional
import logging
from pydantic import BaseModel
from fastapi import APIRouter, HTTPException, Depends
from app.services.embedding import EmbeddingService
from app.services.extraction import ExtractionService, get_extraction_service
from app.services.profile import ProfileService
from app.services.memory import MemoryService, get_memory_service

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/memory", tags=['memory'])


def is_api_overloaded(e: Exception) -> bool:
    """Check if exception is due to API overload (503/429)"""
    error_str = str(e).lower()
    return "503" in error_str or "overloaded" in error_str or "unavailable" in error_str or "429" in error_str


class AddMemoryRequest(BaseModel):
    container_tag: str
    content: str
    memory_type: str = "fact"
    category: Optional[str] = None

class SearchRequest(BaseModel):
    container_tag: str
    query: str
    limit: int = 10
    threshold: float = 0.7

class ExtractRequest(BaseModel):
    container_tag: str
    content: str
    context: str = ""

@router.post("/add")
async def add_memory(
    request: AddMemoryRequest, 
    service: MemoryService = Depends(get_memory_service)
    ):
    try:
        memory_id = await service.add_memory(
            container_tag=request.container_tag,
            content=request.content,
            memory_type=request.memory_type,
            category=request.category
        )
        return {"id": memory_id, "status": 'ok'}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        if is_api_overloaded(e):
            logger.warning(f"API overloaded: {e}")
            raise HTTPException(status_code=503, detail="AI service is temporarily overloaded. Please try again later.")
        logger.error(f"Error adding memory: {e}")
        raise HTTPException(status_code=500, detail="Failed to add memory")

@router.post("/search")
async def search_memories(
    request: SearchRequest, 
    service: MemoryService = Depends(get_memory_service)
    ):
    try:
        response = await service.search(
            container_tag=request.container_tag,
            query=request.query,
            limit=request.limit,
            threshold=request.threshold
        )
        return {"results": response}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        if is_api_overloaded(e):
            logger.warning(f"API overloaded: {e}")
            raise HTTPException(status_code=503, detail="AI service is temporarily overloaded. Please try again later.")
        logger.error(f"Error searching memories: {e}")
        raise HTTPException(status_code=500, detail="Failed to search memories")

@router.post("/extract")
async def extract_and_store(
    request: ExtractRequest, 
    memory_service: MemoryService = Depends(get_memory_service), 
    extract_service: ExtractionService = Depends(get_extraction_service)
    ):
    try:
        memories = await extract_service.extract_memories(
            content=request.content,
            context=request.context
        )
        
        stored = []
        for mem in memories:
            memory_id = await memory_service.add_memory(
                container_tag=request.container_tag,
                content=mem['content'],
                memory_type=mem['type'],
                category=mem.get('category')
            )
            stored.append({"id": memory_id, "content": mem['content']})
        return {"extracted": len(stored), "memories": stored}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        if is_api_overloaded(e):
            logger.warning(f"API overloaded: {e}")
            raise HTTPException(status_code=503, detail="AI service is temporarily overloaded. Please try again later.")
        logger.error(f"Error extracting memories: {e}")
        raise HTTPException(status_code=500, detail="Failed to extract and store memories")