# AI Memory System Implementation Guide

## Supabase Schema Overview

This document describes the memory system database schema I've created in Supabase and how to integrate it with your FastAPI backend.

---

## 📊 Database Schema

### Tables Created

| Table | Purpose |
|-------|---------|
| `memory_containers` | Groups memories by user/entity |
| `memory_documents` | Raw inputs before processing |
| `memories` | Extracted knowledge units with embeddings |
| `memory_relationships` | Graph connections between memories |
| `memory_profiles` | Cached user context (static + dynamic) |
| `memory_conversations` | Conversation history storage |

### Entity Relationship Diagram

```
┌─────────────────────┐
│  memory_containers  │
│  (user groupings)   │
└─────────┬───────────┘
          │ 1:N
          ▼
┌─────────────────────┐      ┌─────────────────────┐
│  memory_documents   │      │ memory_conversations │
│   (raw inputs)      │      │   (chat history)     │
└─────────┬───────────┘      └─────────────────────┘
          │ 1:N
          ▼
┌─────────────────────┐      ┌─────────────────────┐
│     memories        │◄────►│ memory_relationships│
│ (knowledge units)   │      │   (graph edges)     │
└─────────┬───────────┘      └─────────────────────┘
          │ 1:1
          ▼
┌─────────────────────┐
│  memory_profiles    │
│ (cached summaries)  │
└─────────────────────┘
```

---

## 📋 Table Details

### 1. `memory_containers`

Groups memories by user or context (farm, session, etc.)

```sql
-- Key columns:
- id: UUID (primary key)
- tag: VARCHAR(100) UNIQUE  -- e.g., 'user-abc123', 'farm-xyz-context'
- user_id: UUID             -- References auth.users
- container_type: VARCHAR   -- 'user', 'farm', 'session', 'global'
- metadata: JSONB
```

**Usage in FastAPI:**
```python
# Create container for a user
container_tag = f"user-{user_id}"

# Create container for farm-specific context
container_tag = f"farm-{farm_id}-context"
```

### 2. `memory_documents`

Stores raw content before it's processed into memories.

```sql
-- Key columns:
- id: UUID
- container_id: UUID        -- Foreign key to containers
- content: TEXT             -- The raw content
- content_type: VARCHAR     -- 'text', 'url', 'pdf', 'conversation', 'image'
- status: VARCHAR           -- Processing status (see pipeline below)
- metadata: JSONB
```

**Processing Status Pipeline:**
```
queued → extracting → chunking → embedding → indexing → done
                                                    ↓
                                                 failed
```

### 3. `memories`

The core table - extracted knowledge units with vector embeddings.

```sql
-- Key columns:
- id: UUID
- container_id: UUID
- content: TEXT              -- The memory content
- summary: TEXT              -- Short summary
- embedding: vector(768)     -- Gemini embedding (768 dimensions)
- memory_type: VARCHAR       -- 'fact', 'preference', 'episode', 'procedure', 'goal'
- category: VARCHAR          -- Domain: 'animal_health', 'feeding', etc.
- importance: FLOAT          -- 0.0 to 1.0
- confidence: FLOAT          -- How certain we are
- is_latest: BOOLEAN         -- For update tracking
- expires_at: TIMESTAMPTZ    -- For episodic memories
- tags: TEXT[]               -- Searchable tags
```

**Memory Types:**

| Type | Description | Example | Persistence |
|------|-------------|---------|-------------|
| `fact` | Factual information | "User has 50 cows" | Until updated |
| `preference` | User preferences | "Prefers metric units" | Strengthens over time |
| `episode` | Recent events | "Checked cow health today" | Expires |
| `procedure` | How to do things | "How to record weight" | Permanent |
| `goal` | User goals | "Wants to improve milk yield" | Until achieved |

### 4. `memory_relationships`

Graph connections between memories.

```sql
-- Key columns:
- source_memory_id: UUID     -- The newer/derived memory
- target_memory_id: UUID     -- The older/source memory
- relationship_type: VARCHAR -- 'updates', 'extends', 'derives', 'contradicts', 'supports'
- confidence: FLOAT
- reason: TEXT               -- Why this relationship exists
```

**Relationship Types:**

| Type | When Used | Example |
|------|-----------|---------|
| `updates` | New info replaces old | "Farm now has 60 cows" updates "Farm has 50 cows" |
| `extends` | New info adds detail | "Cows are Holstein breed" extends "Farm has cows" |
| `derives` | Inferred from pattern | "User is experienced farmer" derived from multiple interactions |
| `contradicts` | Conflicting info | Used for conflict resolution |
| `supports` | Corroborating info | Multiple sources confirm same fact |

### 5. `memory_profiles`

Cached user context for quick retrieval.

```sql
-- Key columns:
- container_id: UUID
- static_facts: JSONB        -- Always-relevant facts
- dynamic_context: JSONB     -- Recent/episodic context
- is_stale: BOOLEAN          -- Needs regeneration
```

**Profile Structure:**
```json
{
  "static": [
    "User manages Sunrise Farm with 50 dairy cows",
    "User prefers English language",
    "User is interested in animal health tracking"
  ],
  "dynamic": [
    "Recently checked health records for cow TAG-001",
    "Asked about milk production trends yesterday"
  ]
}
```

### 6. `memory_conversations`

Stores conversation history for context.

```sql
-- Key columns:
- container_id: UUID
- session_id: UUID           -- Groups messages in a session
- role: VARCHAR              -- 'user', 'assistant', 'system'
- content: TEXT
- function_call: JSONB       -- If assistant called a function
- tool_calls: JSONB          -- If assistant used tools
```

---

## 🔧 Database Functions

I've created these RPC functions that your FastAPI backend can call directly:

### 1. `search_memories`

Vector similarity search for memories.

```python
# FastAPI usage:
result = supabase.rpc('search_memories', {
    'query_embedding': embedding_list,  # 768-dimensional vector
    'p_container_tag': 'user-abc123',
    'match_threshold': 0.7,
    'match_count': 10,
    'p_memory_type': 'fact',  # Optional filter
    'p_category': 'animal_health',  # Optional filter
    'include_expired': False
}).execute()
```

**Returns:**
```python
[
    {
        'id': 'uuid',
        'content': 'memory content',
        'summary': 'short summary',
        'memory_type': 'fact',
        'category': 'animal_health',
        'importance': 0.8,
        'similarity': 0.92,
        'created_at': '2026-02-01T...',
        'metadata': {}
    }
]
```

### 2. `search_memories_hybrid`

Combined vector + keyword search.

```python
result = supabase.rpc('search_memories_hybrid', {
    'query_embedding': embedding_list,
    'query_text': 'cow health vaccination',
    'p_container_tag': 'user-abc123',
    'match_threshold': 0.5,
    'match_count': 10
}).execute()
```

### 3. `get_or_create_container`

Creates a container if it doesn't exist.

```python
container_id = supabase.rpc('get_or_create_container', {
    'p_tag': 'user-abc123',
    'p_user_id': user_uuid,
    'p_container_type': 'user'
}).execute()
```

### 4. `add_memory`

Adds a new memory to a container.

```python
memory_id = supabase.rpc('add_memory', {
    'p_container_tag': 'user-abc123',
    'p_content': 'User prefers to see weights in kilograms',
    'p_memory_type': 'preference',
    'p_category': 'user_preference',
    'p_embedding': embedding_list,
    'p_metadata': {'source': 'conversation'},
    'p_expires_at': None  # Or ISO timestamp for episodes
}).execute()
```

### 5. `update_memory`

Updates a memory and creates relationship.

```python
new_memory_id = supabase.rpc('update_memory', {
    'p_old_memory_id': 'old-uuid',
    'p_new_content': 'User now has 60 dairy cows',
    'p_new_embedding': new_embedding_list,
    'p_reason': 'User mentioned farm expansion'
}).execute()
```

### 6. `get_memory_profile`

Gets user profile with optional search.

```python
profile = supabase.rpc('get_memory_profile', {
    'p_container_tag': 'user-abc123',
    'p_query_embedding': embedding_list,  # Optional
    'p_query_text': 'cow health',  # Optional
    'p_include_search': True,
    'p_search_limit': 5
}).execute()
```

**Returns:**
```python
{
    'profile': {
        'static': ['fact1', 'fact2', ...],
        'dynamic': ['recent1', 'recent2', ...]
    },
    'search_results': [
        {'id': 'uuid', 'content': '...', 'similarity': 0.9}
    ]
}
```

### 7. `expire_old_memories`

Cleanup function for scheduled jobs.

```python
# Call this from a scheduled task (daily)
expired_count = supabase.rpc('expire_old_memories').execute()
```

### 8. `record_memory_access`

Tracks memory usage for importance scoring.

```python
supabase.rpc('record_memory_access', {
    'p_memory_id': 'memory-uuid'
}).execute()
```

---

## 🐍 FastAPI Integration

Here's how to structure your FastAPI backend:

### Project Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── config.py
│   │
│   ├── api/
│   │   ├── __init__.py
│   │   └── v1/
│   │       ├── memory.py      # Memory endpoints
│   │       ├── search.py      # Search endpoints
│   │       └── profile.py     # Profile endpoints
│   │
│   ├── services/
│   │   ├── __init__.py
│   │   ├── embedding.py       # Gemini embedding generation
│   │   ├── extraction.py      # Memory extraction from text
│   │   ├── memory.py          # Memory CRUD operations
│   │   ├── relationship.py    # Relationship detection
│   │   └── profile.py         # Profile generation
│   │
│   ├── schemas/
│   │   ├── __init__.py
│   │   ├── memory.py
│   │   └── profile.py
│   │
│   └── core/
│       ├── __init__.py
│       ├── supabase.py        # Supabase client
│       └── gemini.py          # Gemini client
│
├── requirements.txt
└── .env
```

### Key Services

#### 1. Embedding Service (Gemini)

```python
# app/services/embedding.py
import google.generativeai as genai
from typing import List

class EmbeddingService:
    def __init__(self, api_key: str):
        genai.configure(api_key=api_key)
        self.model = "models/embedding-001"
    
    async def embed_text(self, text: str) -> List[float]:
        """Generate embedding for text using Gemini."""
        result = genai.embed_content(
            model=self.model,
            content=text,
            task_type="retrieval_document"
        )
        return result['embedding']  # Returns 768-dimensional vector
    
    async def embed_query(self, query: str) -> List[float]:
        """Generate embedding for search query."""
        result = genai.embed_content(
            model=self.model,
            content=query,
            task_type="retrieval_query"
        )
        return result['embedding']
```

#### 2. Memory Service

```python
# app/services/memory.py
from supabase import Client
from typing import List, Dict, Optional
from .embedding import EmbeddingService

class MemoryService:
    def __init__(self, supabase: Client, embedding_service: EmbeddingService):
        self.supabase = supabase
        self.embedding = embedding_service
    
    async def add_memory(
        self,
        container_tag: str,
        content: str,
        memory_type: str = "fact",
        category: Optional[str] = None,
        expires_at: Optional[str] = None,
        metadata: Dict = {}
    ) -> str:
        """Add a new memory with embedding."""
        # Generate embedding
        embedding = await self.embedding.embed_text(content)
        
        # Call Supabase RPC
        result = self.supabase.rpc('add_memory', {
            'p_container_tag': container_tag,
            'p_content': content,
            'p_memory_type': memory_type,
            'p_category': category,
            'p_embedding': embedding,
            'p_metadata': metadata,
            'p_expires_at': expires_at
        }).execute()
        
        return result.data
    
    async def search(
        self,
        container_tag: str,
        query: str,
        limit: int = 10,
        threshold: float = 0.7,
        memory_type: Optional[str] = None
    ) -> List[Dict]:
        """Search memories by semantic similarity."""
        # Generate query embedding
        query_embedding = await self.embedding.embed_query(query)
        
        # Call Supabase RPC
        result = self.supabase.rpc('search_memories', {
            'query_embedding': query_embedding,
            'p_container_tag': container_tag,
            'match_threshold': threshold,
            'match_count': limit,
            'p_memory_type': memory_type,
            'p_category': None,
            'include_expired': False
        }).execute()
        
        return result.data
```

#### 3. Extraction Service

```python
# app/services/extraction.py
import google.generativeai as genai
from typing import List, Dict
import json

class ExtractionService:
    def __init__(self, api_key: str):
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel('gemini-2.0-flash')
    
    async def extract_memories(self, content: str, context: str = "") -> List[Dict]:
        """Extract discrete memories from content using Gemini."""
        
        prompt = f"""Analyze this conversation/text and extract discrete facts, preferences, 
        and episodic memories. For each memory:
        
        1. content: A single fact, preference, or event (be specific and standalone)
        2. type: 'fact' (permanent info), 'preference' (user likes/dislikes), 'episode' (recent event)
        3. category: Domain category like 'animal_health', 'farm_management', 'user_preference', 'feeding', etc.
        4. importance: 0.0 to 1.0 (how important is this to remember?)
        5. expires_hours: null for permanent, or number of hours for episodes
        
        Context about the user/farm:
        {context}
        
        Content to analyze:
        {content}
        
        Return ONLY a JSON array:
        [
            {{
                "content": "extracted memory",
                "type": "fact|preference|episode",
                "category": "category_name",
                "importance": 0.8,
                "expires_hours": null
            }}
        ]
        """
        
        response = self.model.generate_content(prompt)
        
        # Parse JSON from response
        try:
            # Extract JSON from response text
            text = response.text
            # Find JSON array in response
            start = text.find('[')
            end = text.rfind(']') + 1
            if start != -1 and end > start:
                return json.loads(text[start:end])
        except json.JSONDecodeError:
            pass
        
        return []
```

#### 4. Profile Service

```python
# app/services/profile.py
from supabase import Client
from typing import Dict, Optional
from .embedding import EmbeddingService

class ProfileService:
    def __init__(self, supabase: Client, embedding_service: EmbeddingService):
        self.supabase = supabase
        self.embedding = embedding_service
    
    async def get_profile(
        self,
        container_tag: str,
        query: Optional[str] = None,
        include_search: bool = True
    ) -> Dict:
        """Get user profile with optional search results."""
        
        query_embedding = None
        if query and include_search:
            query_embedding = await self.embedding.embed_query(query)
        
        result = self.supabase.rpc('get_memory_profile', {
            'p_container_tag': container_tag,
            'p_query_embedding': query_embedding,
            'p_query_text': query,
            'p_include_search': include_search,
            'p_search_limit': 5
        }).execute()
        
        return result.data
    
    def build_context_prompt(self, profile: Dict) -> str:
        """Build context string for LLM prompt."""
        static = profile.get('profile', {}).get('static', [])
        dynamic = profile.get('profile', {}).get('dynamic', [])
        search_results = profile.get('search_results', [])
        
        context_parts = []
        
        if static:
            context_parts.append("## User Profile (Always Relevant)")
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
```

### API Endpoints

```python
# app/api/v1/memory.py
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from ...services.memory import MemoryService
from ...services.extraction import ExtractionService
from ...core.deps import get_memory_service, get_extraction_service

router = APIRouter(prefix="/memory", tags=["Memory"])

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
    """Add a single memory."""
    memory_id = await service.add_memory(
        container_tag=request.container_tag,
        content=request.content,
        memory_type=request.memory_type,
        category=request.category
    )
    return {"id": memory_id, "status": "created"}

@router.post("/search")
async def search_memories(
    request: SearchRequest,
    service: MemoryService = Depends(get_memory_service)
):
    """Search memories by semantic similarity."""
    results = await service.search(
        container_tag=request.container_tag,
        query=request.query,
        limit=request.limit,
        threshold=request.threshold
    )
    return {"results": results}

@router.post("/extract")
async def extract_and_store(
    request: ExtractRequest,
    memory_service: MemoryService = Depends(get_memory_service),
    extraction_service: ExtractionService = Depends(get_extraction_service)
):
    """Extract memories from content and store them."""
    # Extract memories using Gemini
    memories = await extraction_service.extract_memories(
        content=request.content,
        context=request.context
    )
    
    # Store each extracted memory
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
```

---

## 🔄 Workflow: How It All Fits Together

### 1. User Sends Message

```
User: "My cow TAG-001 had her vaccination yesterday"
```

### 2. Get Context (Profile + Search)

```python
# Get user profile and search for relevant memories
profile = await profile_service.get_profile(
    container_tag=f"user-{user_id}",
    query="cow TAG-001 vaccination"
)

context = profile_service.build_context_prompt(profile)
```

### 3. Generate Response with Context

```python
# Build prompt with memory context
system_prompt = f"""You are a helpful farm management assistant.

{context}

Use this context to provide personalized responses.
"""

# Call Gemini
response = model.generate_content([
    {"role": "user", "parts": [system_prompt]},
    {"role": "user", "parts": [user_message]}
])
```

### 4. Extract & Store New Memories

```python
# Extract memories from the conversation
conversation = f"User: {user_message}\nAssistant: {response.text}"

memories = await extraction_service.extract_memories(
    content=conversation,
    context=context
)

# Store extracted memories
for mem in memories:
    await memory_service.add_memory(
        container_tag=f"user-{user_id}",
        content=mem['content'],
        memory_type=mem['type'],
        category=mem.get('category')
    )
```

---

## 📅 Categories for Farm Manager

Use these categories to organize memories:

| Category | Examples |
|----------|----------|
| `animal_health` | Vaccination records, health issues, treatments |
| `animal_info` | Species, breed, birth dates, tag IDs |
| `feeding` | Feed schedules, dietary preferences, amounts |
| `breeding` | Breeding history, pregnancy status |
| `production` | Milk yield, weight records |
| `farm_management` | Staff info, equipment, schedules |
| `financial` | Costs, sales, budgets |
| `user_preference` | Language, units, display preferences |
| `user_goal` | What the user wants to achieve |

---

## 🔐 Security Notes

1. **RLS is enabled** on all tables - users can only access their own data
2. **Service role** has full access - use it in your FastAPI backend
3. **Container tags** include user ID for isolation: `user-{user_id}`
4. **Never expose** the service role key to clients

---

## 🚀 Next Steps

### Your FastAPI Tasks:
1. Set up Supabase client with service role key
2. Implement EmbeddingService with Gemini
3. Implement ExtractionService with Gemini
4. Create API endpoints for memory operations
5. Integrate with your existing assistant endpoints

### I Can Help With:
- Creating Edge Functions for background processing
- Setting up pg_cron for scheduled memory expiration
- Adding more specialized search functions
- Creating indexes for specific query patterns

---

## 📞 Quick Reference: Supabase RPC Calls

| Function | Purpose | Key Params |
|----------|---------|------------|
| `get_or_create_container` | Create user container | tag, user_id |
| `add_memory` | Store new memory | container_tag, content, embedding |
| `update_memory` | Update existing memory | old_id, new_content, new_embedding |
| `search_memories` | Vector similarity search | embedding, container_tag, threshold |
| `search_memories_hybrid` | Vector + keyword search | embedding, text, container_tag |
| `get_memory_profile` | Get user context | container_tag, query_embedding |
| `expire_old_memories` | Cleanup job | (none) |
| `record_memory_access` | Track usage | memory_id |

---

*Created: February 1, 2026*
