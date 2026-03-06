from google import genai
from google.genai.types import EmbedContentConfig
from typing import List

class EmbeddingService:
    def __init__(self, api_key: str):
        self.client = genai.Client(api_key=api_key)
        self.model = "gemini-embedding-001"
    
    async def embed_text(self, text: str) -> List[float]:
        """
        Generate embeddings for the given text using Gemini Embedding model.
        Args:
            text (str): The input text to be embedded.
        Returns:
            List[float]: The embedding vector.
        """
        result = await self.client.aio.models.embed_content(
            model= self.model,
            contents=text,
            config=EmbedContentConfig(
                task_type="retrieval_document",
                output_dimensionality=768,

            )
        )
        return result.embeddings[0].values

    async def embed_query(self, query: str) -> List[float]:
        """
        Generate embeddings for the given text using Gemini Embedding model.
        Args:
            query (str): The input text to be embedded.
        Returns:
            List[float]: The embedding vector.
        """
        result = await self.client.aio.models.embed_content(
            model= self.model,
            contents=query,
            config=EmbedContentConfig(
                task_type="retrieval_query",
                output_dimensionality=768,

            )
        )
        return result.embeddings[0].values

 