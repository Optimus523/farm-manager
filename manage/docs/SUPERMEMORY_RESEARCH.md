# Supermemory: The Memory Infrastructure for AI Agents

## A Comprehensive Research & Implementation Guide

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [What is Supermemory?](#what-is-supermemory)
3. [Core Architecture](#core-architecture)
4. [How It Works](#how-it-works)
5. [Key Features](#key-features)
6. [Memory vs Traditional RAG](#memory-vs-traditional-rag)
7. [Technical Deep Dive](#technical-deep-dive)
8. [API Overview](#api-overview)
9. [Use Cases](#use-cases)
10. [Building a Similar System with FastAPI](#building-a-similar-system-with-fastapi)
11. [Implementation Roadmap](#implementation-roadmap)
12. [Conclusion](#conclusion)

---

## Executive Summary

**Supermemory** is a context engineering infrastructure designed to give AI agents persistent, evolving memory. Unlike traditional vector databases or RAG (Retrieval-Augmented Generation) systems that merely retrieve static documents, Supermemory creates a **living knowledge graph** that understands relationships, tracks changes over time, and even "forgets" irrelevant information—mimicking how human memory actually works.

### Key Statistics
- **16,000+ GitHub stars** with 1,600+ forks
- **Sub-300ms recall latency**
- Scales to **50 million tokens per user**
- Handles **5+ billion tokens daily** for enterprise customers
- Trusted by **70+ Y Combinator companies** and **10,000+ developers**
- **SOC 2 compliant** with enterprise-grade security

---

## What is Supermemory?

Supermemory positions itself as "the context engineering infrastructure for AI agents." At its core, it solves a fundamental problem:

> **"Your AI isn't intelligent until it remembers."**

### The Problem with Current AI Systems

1. **Context Window Limitations**: LLMs have finite context windows and lose information between sessions
2. **Vector Database Failures**: Traditional vector DBs store static embeddings without understanding relationships
3. **RAG Limitations**: RAG systems retrieve knowledge but can't truly "remember" or evolve
4. **No Personalization**: Each interaction starts fresh without user context

### Supermemory's Solution

Supermemory provides:
- **Persistent user profiles** that evolve over time
- **Intelligent memory extraction** from conversations, documents, and media
- **Graph-based relationships** between memories
- **Automatic forgetting** of irrelevant or outdated information
- **Sub-second recall** with semantic understanding

---

## Core Architecture

Supermemory's architecture consists of several key components:

### 1. Vector-Graph Hybrid Engine

Unlike pure vector databases, Supermemory combines:
- **Vector embeddings** for semantic similarity search
- **Graph database** for relationship tracking
- **Temporal indexing** for time-aware queries

### 2. Technology Stack

Based on their GitHub repository:
- **Backend**: TypeScript (67.5%), Python (4.6%)
- **Database**: PostgreSQL with custom vector extensions
- **Edge Computing**: Cloudflare Workers, Cloudflare Durable Objects, Cloudflare KV
- **Frontend**: Remix, Tailwind CSS, Vite
- **ORM**: Drizzle ORM
- **Documentation**: MDX (27.4%)

### 3. Infrastructure Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    APPLICATION LAYER                        │
│  (Chrome Extension, Raycast, MCP Integration, Web App)      │
├─────────────────────────────────────────────────────────────┤
│                       API LAYER                             │
│     (REST API v3, TypeScript SDK, Python SDK)               │
├─────────────────────────────────────────────────────────────┤
│                   PROCESSING PIPELINE                       │
│  Extraction → Chunking → Embedding → Indexing → Enrichment  │
├─────────────────────────────────────────────────────────────┤
│                    STORAGE LAYER                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Vector Store │  │ Graph Store  │  │   Metadata   │       │
│  │  (Semantic)  │  │(Relationships)│  │   (Facts)    │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
├─────────────────────────────────────────────────────────────┤
│                 INFRASTRUCTURE LAYER                        │
│      (PostgreSQL, Cloudflare Workers, Durable Objects)      │
└─────────────────────────────────────────────────────────────┘
```

---

## How It Works

### The Six-Stage Processing Pipeline

#### Stage 1: CONNECT
Plug Supermemory into your stack in minutes with SDKs for:
- OpenAI
- Anthropic
- Vercel AI SDK
- Cloudflare
- LangChain (recently added)

#### Stage 2: INGEST
Accept any type of data:
- Text and conversations
- URLs and web pages
- PDFs and documents
- Images (with OCR)
- Videos (with transcription)
- Files from Google Drive, Notion, OneDrive

#### Stage 3: EMBED + ENRICH
- Generate semantic embeddings
- Extract facts and entities
- Build graph-based connections
- Link related memories across contexts

#### Stage 4: INDEX + STORE
- Index into both vector store and graph database
- Enable hybrid search (semantic + keyword)
- Ensure sub-300ms recall times

#### Stage 5: RECALL
Retrieve the right memory instantly:
- Semantic similarity search
- Keyword matching
- Temporal filtering
- Relationship traversal

#### Stage 6: EVOLVE
Memory that changes over time:
- **Updates**: New facts replace outdated ones
- **Extensions**: New details enrich existing memories
- **Derivations**: Inferences create new connections
- **Expiration**: Irrelevant memories are forgotten

---

## Key Features

### 1. Documents vs Memories

**Documents** are raw inputs:
- PDF files
- Web pages
- Text content
- Images and videos

**Memories** are intelligent knowledge units:
- Semantic chunks with meaning
- Embedded for similarity search
- Connected through relationships
- Dynamically updated

> **Key Insight**: A 50-page PDF becomes hundreds of interconnected memories, each understanding its context and relationships.

### 2. Memory Relationships

Supermemory tracks three types of relationships:

#### Updates (Information Changes)
```
Memory 1: "Alex works at Google as a software engineer"
Memory 2: "Alex just started at Stripe as a PM"
         ↓
Memory 2 UPDATES Memory 1
```
The system tracks `isLatest` to return current information while preserving history.

#### Extends (Information Enriches)
```
Memory 1: "Alex works at Stripe as a PM"
Memory 2: "Alex focuses on payments infrastructure and leads a team of 5"
         ↓
Memory 2 EXTENDS Memory 1
```
Both memories remain valid, providing richer context.

#### Derives (Information Infers)
```
Memory 1: "Alex is a PM at Stripe"
Memory 2: "Alex frequently discusses payment APIs"
         ↓
Derived: "Alex likely works on Stripe's core payments product"
```
Automatic inferences surface insights not explicitly stated.

### 3. Automatic Memory Extraction

From a single conversation:
> "Had a great call with Alex. He's enjoying the new PM role at Stripe, though the payments infrastructure work is intense. He moved to Seattle for the job—got a place in Capitol Hill. Wants to grab dinner next time I'm in town."

Supermemory extracts:
- Alex works at Stripe as a PM
- Alex works on payments infrastructure (extends role memory)
- Alex lives in Seattle, Capitol Hill (new fact)
- Alex wants to meet for dinner (episodic)

### 4. Automatic Forgetting

**Time-based forgetting**:
```
"I have an exam tomorrow"
    ↓ After exam date passes → automatically forgotten

"Meeting with Alex at 3pm today"
    ↓ After today → automatically forgotten
```

**Contradiction resolution**: Updates supersede old facts

**Noise filtering**: Casual content doesn't become permanent

### 5. Memory Types

| Type | Example | Behavior |
|------|---------|----------|
| Facts | "Alex is a PM at Stripe" | Persists until updated |
| Preferences | "Alex prefers morning meetings" | Strengthens with repetition |
| Episodes | "Met Alex for coffee Tuesday" | Decays unless significant |

### 6. User Profiles

Automatic summaries combining:
- **Static**: Information the agent should always know
- **Dynamic**: Episodic information about recent conversations

---

## Memory vs Traditional RAG

| Aspect | Traditional RAG | Supermemory |
|--------|-----------------|-------------|
| **Storage** | Static document chunks | Living knowledge graph |
| **Relationships** | None | Updates, Extensions, Derivations |
| **Time Awareness** | None | Temporal tracking, forgetting |
| **User Context** | None | Persistent profiles |
| **Information Updates** | Manual re-indexing | Automatic evolution |
| **Noise Handling** | Everything stored | Intelligent filtering |
| **Inferences** | None | Automatic derivations |

---

## Technical Deep Dive

### Processing Pipeline States

| Status | Description |
|--------|-------------|
| Queued | Document waiting to process |
| Extracting | Content being extracted |
| Chunking | Creating memory chunks |
| Embedding | Generating vectors |
| Indexing | Building relationships |
| Done | Fully searchable |

### API Endpoints

#### Add Document
```python
POST /v3/documents
{
  "content": "<string>",           # URL, text, or file
  "containerTag": "user-123",      # User/entity identifier
  "customId": "doc-456",           # Optional custom ID
  "metadata": {}                   # Optional metadata
}
```

#### Search Memories
```python
POST /v3/search
{
  "query": "where does Alex work?",
  "containerTag": "user-123",
  "threshold": 0.7                 # Relevance score filter
}
```

#### Get User Profile
```python
POST /v3/profile
{
  "containerTag": "user-123",
  "q": "What should I know about this user?"
}
```

### Python SDK Example

```python
from supermemory import Supermemory

client = Supermemory()
USER_ID = "dhravya"

conversation = [
    {"role": "assistant", "content": "Hello, how are you doing?"},
    {"role": "user", "content": "I am Dhravya. I'm 20 and love coding!"},
]

# Get user profile + relevant memories
profile = client.profile(container_tag=USER_ID, q=conversation[-1]["content"])

# Build context
static = "\n".join(profile.profile.static)
dynamic = "\n".join(profile.profile.dynamic)
memories = "\n".join(r.get("memory", "") for r in profile.search_results.results)

context = f"""Static profile:
{static}

Dynamic profile:
{dynamic}

Relevant memories:
{memories}"""

# Use with any LLM
messages = [{"role": "system", "content": f"User context:\n{context}"}, *conversation]

# Store conversation for future context
client.add(
    content="\n".join(f"{m['role']}: {m['content']}" for m in conversation),
    container_tag=USER_ID,
)
```

---

## Use Cases

### 1. AI Assistants
- Remember user preferences, roles, and context
- Surface insights from past conversations
- Power workflows with persistent context

### 2. Education
- Track student progress and learning patterns
- Personalize content recommendations
- Remember teaching history

### 3. Healthcare
- Patient history tracking
- Treatment context awareness
- Compliance-friendly data handling

### 4. Legal
- Case history and precedent tracking
- Client context management
- Document relationship mapping

### 5. Knowledge Hubs
- Cross-document insights
- Organizational memory
- Research connection discovery

---

## Building a Similar System with FastAPI

Since you mentioned you have a FastAPI backend, here's a conceptual architecture for building a Supermemory-like system:

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    FASTAPI APPLICATION                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   Ingest     │  │   Memory     │  │   Profile    │       │
│  │   Router     │  │   Router     │  │   Router     │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                    SERVICE LAYER                             │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │  Extraction  │  │  Embedding   │  │   Graph      │       │
│  │   Service    │  │   Service    │  │   Service    │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   Memory     │  │   Profile    │  │   Search     │       │
│  │   Service    │  │   Service    │  │   Service    │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                    DATA LAYER                                │
│                                                              │
│  ┌──────────────────────────────────────────────────┐       │
│  │                  PostgreSQL                        │       │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐           │       │
│  │  │ pgvector│  │ Tables  │  │ JSONB   │           │       │
│  │  │(vectors)│  │(memories)│ │(metadata)│           │       │
│  │  └─────────┘  └─────────┘  └─────────┘           │       │
│  └──────────────────────────────────────────────────┘       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Database Schema (PostgreSQL with pgvector)

```sql
-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Users/Containers table
CREATE TABLE containers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tag VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Documents table (raw inputs)
CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    container_id UUID REFERENCES containers(id),
    custom_id VARCHAR(100),
    content TEXT NOT NULL,
    content_type VARCHAR(50), -- 'text', 'url', 'pdf', 'image', 'video'
    status VARCHAR(20) DEFAULT 'queued',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

-- Memories table (extracted knowledge units)
CREATE TABLE memories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    container_id UUID REFERENCES containers(id),
    document_id UUID REFERENCES documents(id),
    content TEXT NOT NULL,
    memory_type VARCHAR(20), -- 'fact', 'preference', 'episode'
    embedding vector(1536), -- OpenAI ada-002 dimension
    is_latest BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Memory relationships table
CREATE TABLE memory_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_memory_id UUID REFERENCES memories(id),
    target_memory_id UUID REFERENCES memories(id),
    relationship_type VARCHAR(20), -- 'updates', 'extends', 'derives'
    confidence FLOAT DEFAULT 1.0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User profiles table (cached summaries)
CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    container_id UUID UNIQUE REFERENCES containers(id),
    static_facts JSONB DEFAULT '[]',
    dynamic_context JSONB DEFAULT '[]',
    last_updated TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_memories_container ON memories(container_id);
CREATE INDEX idx_memories_embedding ON memories USING ivfflat (embedding vector_cosine_ops);
CREATE INDEX idx_memories_latest ON memories(container_id, is_latest) WHERE is_latest = TRUE;
CREATE INDEX idx_documents_status ON documents(status);
```

### FastAPI Implementation Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── config.py
│   │
│   ├── api/
│   │   ├── __init__.py
│   │   ├── deps.py
│   │   └── v1/
│   │       ├── __init__.py
│   │       ├── documents.py
│   │       ├── memories.py
│   │       ├── search.py
│   │       └── profiles.py
│   │
│   ├── core/
│   │   ├── __init__.py
│   │   ├── security.py
│   │   └── exceptions.py
│   │
│   ├── models/
│   │   ├── __init__.py
│   │   ├── document.py
│   │   ├── memory.py
│   │   ├── relationship.py
│   │   └── profile.py
│   │
│   ├── schemas/
│   │   ├── __init__.py
│   │   ├── document.py
│   │   ├── memory.py
│   │   └── profile.py
│   │
│   ├── services/
│   │   ├── __init__.py
│   │   ├── extraction.py      # Content extraction (text, PDF, URL)
│   │   ├── chunking.py        # Smart text chunking
│   │   ├── embedding.py       # Vector embedding generation
│   │   ├── memory.py          # Memory creation & management
│   │   ├── relationship.py    # Graph relationship detection
│   │   ├── search.py          # Hybrid search (vector + keyword)
│   │   ├── profile.py         # User profile generation
│   │   └── forgetting.py      # Automatic memory expiration
│   │
│   ├── tasks/
│   │   ├── __init__.py
│   │   └── processing.py      # Background document processing
│   │
│   └── db/
│       ├── __init__.py
│       ├── session.py
│       └── repositories/
│           ├── document.py
│           ├── memory.py
│           └── profile.py
│
├── tests/
├── alembic/
├── requirements.txt
└── docker-compose.yml
```

### Key Service Implementations

#### 1. Embedding Service

```python
# services/embedding.py
from openai import OpenAI
from typing import List
import numpy as np

class EmbeddingService:
    def __init__(self):
        self.client = OpenAI()
        self.model = "text-embedding-ada-002"
    
    async def embed_text(self, text: str) -> List[float]:
        """Generate embedding for a single text."""
        response = self.client.embeddings.create(
            input=text,
            model=self.model
        )
        return response.data[0].embedding
    
    async def embed_batch(self, texts: List[str]) -> List[List[float]]:
        """Generate embeddings for multiple texts."""
        response = self.client.embeddings.create(
            input=texts,
            model=self.model
        )
        return [item.embedding for item in response.data]
    
    def cosine_similarity(self, vec1: List[float], vec2: List[float]) -> float:
        """Calculate cosine similarity between two vectors."""
        a = np.array(vec1)
        b = np.array(vec2)
        return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))
```

#### 2. Memory Extraction Service

```python
# services/extraction.py
from openai import OpenAI
from typing import List, Dict
import json

class ExtractionService:
    def __init__(self):
        self.client = OpenAI()
    
    async def extract_memories(self, content: str) -> List[Dict]:
        """Extract discrete facts/memories from content."""
        
        prompt = """Analyze the following content and extract discrete facts, 
        preferences, and episodic memories. For each memory, determine:
        1. The memory content (a single fact or preference)
        2. The memory type: 'fact', 'preference', or 'episode'
        3. Whether it has a temporal expiration (for episodes)
        
        Return as JSON array:
        [
            {
                "content": "extracted memory",
                "type": "fact|preference|episode",
                "expires": null or ISO date string
            }
        ]
        
        Content:
        {content}
        """
        
        response = self.client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "You are a memory extraction system."},
                {"role": "user", "content": prompt.format(content=content)}
            ],
            response_format={"type": "json_object"}
        )
        
        result = json.loads(response.choices[0].message.content)
        return result.get("memories", [])
```

#### 3. Relationship Detection Service

```python
# services/relationship.py
from typing import List, Optional, Tuple
from sqlalchemy.orm import Session
from models.memory import Memory
from services.embedding import EmbeddingService

class RelationshipService:
    def __init__(self, db: Session, embedding_service: EmbeddingService):
        self.db = db
        self.embedding_service = embedding_service
        self.similarity_threshold = 0.85
    
    async def detect_relationships(
        self, 
        new_memory: Memory, 
        existing_memories: List[Memory]
    ) -> List[Tuple[str, Memory, float]]:
        """
        Detect relationships between new memory and existing ones.
        Returns: List of (relationship_type, related_memory, confidence)
        """
        relationships = []
        new_embedding = new_memory.embedding
        
        for existing in existing_memories:
            similarity = self.embedding_service.cosine_similarity(
                new_embedding, 
                existing.embedding
            )
            
            if similarity > self.similarity_threshold:
                rel_type = await self._classify_relationship(
                    new_memory.content, 
                    existing.content
                )
                if rel_type:
                    relationships.append((rel_type, existing, similarity))
        
        return relationships
    
    async def _classify_relationship(
        self, 
        new_content: str, 
        existing_content: str
    ) -> Optional[str]:
        """Classify the relationship type between two memories."""
        # Use LLM to determine if this is an update, extension, or derivation
        prompt = f"""Compare these two memories and determine the relationship:

        Existing: {existing_content}
        New: {new_content}

        Is the new memory:
        - 'updates': Contradicts or replaces the existing memory
        - 'extends': Adds detail without replacing
        - 'derives': Can be inferred from the existing memory
        - 'none': No significant relationship

        Return only the relationship type word."""
        
        # LLM call to classify...
        # Return the classification
        pass
```

#### 4. Search Service

```python
# services/search.py
from typing import List, Dict, Optional
from sqlalchemy.orm import Session
from sqlalchemy import text
from services.embedding import EmbeddingService

class SearchService:
    def __init__(self, db: Session, embedding_service: EmbeddingService):
        self.db = db
        self.embedding_service = embedding_service
    
    async def hybrid_search(
        self,
        query: str,
        container_tag: str,
        threshold: float = 0.7,
        limit: int = 10
    ) -> List[Dict]:
        """
        Perform hybrid search combining vector similarity and keyword matching.
        """
        # Generate query embedding
        query_embedding = await self.embedding_service.embed_text(query)
        
        # Hybrid search query using pgvector
        sql = text("""
            WITH semantic_results AS (
                SELECT 
                    m.id,
                    m.content,
                    m.memory_type,
                    m.created_at,
                    1 - (m.embedding <=> :embedding::vector) as semantic_score
                FROM memories m
                JOIN containers c ON m.container_id = c.id
                WHERE c.tag = :container_tag
                  AND m.is_latest = TRUE
                  AND (m.expires_at IS NULL OR m.expires_at > NOW())
                ORDER BY m.embedding <=> :embedding::vector
                LIMIT :limit
            ),
            keyword_results AS (
                SELECT 
                    m.id,
                    m.content,
                    m.memory_type,
                    m.created_at,
                    ts_rank(to_tsvector('english', m.content), 
                            plainto_tsquery('english', :query)) as keyword_score
                FROM memories m
                JOIN containers c ON m.container_id = c.id
                WHERE c.tag = :container_tag
                  AND m.is_latest = TRUE
                  AND to_tsvector('english', m.content) @@ 
                      plainto_tsquery('english', :query)
                LIMIT :limit
            )
            SELECT DISTINCT ON (id)
                id, content, memory_type, created_at,
                COALESCE(s.semantic_score, 0) * 0.7 + 
                COALESCE(k.keyword_score, 0) * 0.3 as combined_score
            FROM semantic_results s
            FULL OUTER JOIN keyword_results k USING (id, content, memory_type, created_at)
            WHERE COALESCE(s.semantic_score, 0) >= :threshold
               OR COALESCE(k.keyword_score, 0) > 0
            ORDER BY id, combined_score DESC
            LIMIT :limit
        """)
        
        results = self.db.execute(sql, {
            "embedding": query_embedding,
            "container_tag": container_tag,
            "query": query,
            "threshold": threshold,
            "limit": limit
        })
        
        return [dict(row) for row in results]
```

#### 5. Profile Service

```python
# services/profile.py
from typing import Dict, List
from sqlalchemy.orm import Session
from openai import OpenAI
import json

class ProfileService:
    def __init__(self, db: Session):
        self.db = db
        self.client = OpenAI()
    
    async def generate_profile(
        self, 
        container_tag: str,
        query: Optional[str] = None
    ) -> Dict:
        """
        Generate a user profile combining static facts and dynamic context.
        """
        # Fetch all latest memories for the container
        memories = await self._get_latest_memories(container_tag)
        
        if not memories:
            return {"static": [], "dynamic": [], "search_results": []}
        
        # Generate profile using LLM
        prompt = """Based on these memories about a user, generate a profile with:
        
        1. Static facts: Core information the AI should always know
           (e.g., name, job, location, key preferences)
        
        2. Dynamic context: Recent/episodic information
           (e.g., recent conversations, temporary states, upcoming events)
        
        Memories:
        {memories}
        
        Return as JSON:
        {{
            "static": ["fact1", "fact2", ...],
            "dynamic": ["recent1", "recent2", ...]
        }}
        """
        
        memory_text = "\n".join([m["content"] for m in memories])
        
        response = self.client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "You are a user profile generator."},
                {"role": "user", "content": prompt.format(memories=memory_text)}
            ],
            response_format={"type": "json_object"}
        )
        
        profile = json.loads(response.choices[0].message.content)
        
        # If query provided, also do a search
        search_results = []
        if query:
            search_results = await self.search_service.hybrid_search(
                query=query,
                container_tag=container_tag
            )
        
        return {
            "profile": profile,
            "search_results": search_results
        }
```

### API Router Example

```python
# api/v1/memories.py
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from schemas.document import DocumentCreate, DocumentResponse
from schemas.memory import MemorySearchRequest, MemorySearchResponse
from schemas.profile import ProfileRequest, ProfileResponse
from services.memory import MemoryService
from services.search import SearchService
from services.profile import ProfileService
from api.deps import get_db

router = APIRouter()

@router.post("/documents", response_model=DocumentResponse)
async def add_document(
    request: DocumentCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """
    Add a document to be processed into memories.
    """
    service = MemoryService(db)
    document = await service.create_document(
        content=request.content,
        container_tag=request.container_tag,
        custom_id=request.custom_id,
        metadata=request.metadata
    )
    
    # Process document in background
    background_tasks.add_task(
        service.process_document,
        document.id
    )
    
    return DocumentResponse(
        id=str(document.id),
        status=document.status
    )


@router.post("/search", response_model=MemorySearchResponse)
async def search_memories(
    request: MemorySearchRequest,
    db: Session = Depends(get_db)
):
    """
    Search memories with hybrid semantic + keyword search.
    """
    service = SearchService(db)
    results = await service.hybrid_search(
        query=request.query,
        container_tag=request.container_tag,
        threshold=request.threshold or 0.7,
        limit=request.limit or 10
    )
    
    return MemorySearchResponse(results=results)


@router.post("/profile", response_model=ProfileResponse)
async def get_profile(
    request: ProfileRequest,
    db: Session = Depends(get_db)
):
    """
    Get user profile with static facts and dynamic context.
    """
    service = ProfileService(db)
    profile = await service.generate_profile(
        container_tag=request.container_tag,
        query=request.q
    )
    
    return ProfileResponse(**profile)
```

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Set up PostgreSQL with pgvector extension
- [ ] Create database schema and migrations
- [ ] Implement basic document ingestion API
- [ ] Set up embedding generation service

### Phase 2: Core Memory System (Week 3-4)
- [ ] Implement memory extraction from text
- [ ] Build chunking service with smart boundaries
- [ ] Create vector similarity search
- [ ] Add basic keyword search

### Phase 3: Graph Intelligence (Week 5-6)
- [ ] Implement relationship detection (updates, extends, derives)
- [ ] Build relationship storage and traversal
- [ ] Create `isLatest` tracking for updates
- [ ] Add temporal expiration for episodes

### Phase 4: Profile & Search (Week 7-8)
- [ ] Build hybrid search combining vector + keyword
- [ ] Implement user profile generation
- [ ] Create static/dynamic context separation
- [ ] Add search result ranking and filtering

### Phase 5: Advanced Features (Week 9-10)
- [ ] Add content extraction for URLs, PDFs, images
- [ ] Implement automatic forgetting scheduler
- [ ] Build connectors for external services
- [ ] Create MCP integration for AI tools

### Phase 6: Optimization & Scale (Week 11-12)
- [ ] Optimize vector search with IVF indexes
- [ ] Add caching layer (Redis)
- [ ] Implement rate limiting
- [ ] Set up monitoring and analytics

---

## Conclusion

Supermemory represents a paradigm shift in how we think about AI memory—from static document retrieval to a living, evolving knowledge graph that truly understands and remembers. Its key innovations include:

1. **Graph-based memory relationships** that track how information evolves
2. **Automatic memory extraction** from unstructured content
3. **Intelligent forgetting** that mimics human memory
4. **User profiles** that provide persistent context
5. **Hybrid search** combining semantic understanding with keyword precision

For your FastAPI-based assistant, implementing even a subset of these capabilities would dramatically improve personalization and context awareness. Start with the core memory extraction and vector search, then progressively add relationship detection and profile generation.

### Key Takeaways

1. **Memory ≠ Storage**: True memory involves understanding, relationships, and evolution
2. **Context is King**: User profiles provide the "always-on" context that makes AI feel personal
3. **Forgetting is a Feature**: Automatic expiration prevents information overload
4. **Hybrid Search Wins**: Combining vector similarity with keyword matching provides the best results
5. **Start Simple**: Begin with basic memory storage and search, then add graph intelligence

---

## References

- [Supermemory Website](https://supermemory.ai/)
- [Supermemory Documentation](https://supermemory.ai/docs)
- [Supermemory GitHub Repository](https://github.com/supermemoryai/supermemory)
- [Supermemory Developer Console](https://console.supermemory.ai/)
- [pgvector Documentation](https://github.com/pgvector/pgvector)

---

*Last Updated: February 2026*
