from google import genai
from typing import Dict, List, Optional
import json

from app.core.config import get_settings

class ExtractionService:
    def __init__(self, api_key: str):
        self.client = genai.Client(api_key=api_key)
        self.model = "gemini-3-flash-preview"
        
    async def extract_memories(self, content: str, context: str) -> List[Dict]:
        """
        Extract structured memories from the given content using Gemini model.
        Args:
            content (str): The input content to extract memories from.
        Returns:
            List[Dict]: A list of extracted memories as dictionaries.
        """
        
        prompt = f"""Analyze this farm management conversation/text and extract discrete facts, preferences, 
        and episodic memories. For each memory:
        
        1. content: A single fact, preference, or event (be specific and standalone)
        2. type: 'fact' (permanent info), 'preference' (user likes/dislikes), 'episode' (recent event)
        3. category: Use one of these domain categories:
           - Animal Health: 'vaccination', 'medication', 'treatment', 'checkup', 'surgery', 'observation', 'withdrawal_period', 'follow_up', 'disease', 'symptoms'
           - Farm Operations: 'feeding', 'breeding', 'weight_tracking', 'farm_management'
           - Tools & Workflow: 'tool_usage', 'reminder_preference', 'reporting_preference', 'notification_preference'
           - User: 'user_preference', 'farm_settings', 'workflow_preference'
        4. importance: 0.0 to 1.0 (how important is this to remember?)
           - Health emergencies, disease outbreaks, critical treatments: 0.9-1.0
           - Vaccinations, medications, regular checkups: 0.7-0.8
           - Tool preferences, workflow patterns: 0.6-0.7
           - Observations, general preferences: 0.5-0.6
        5. expires_hours: null for permanent facts, or number of hours for episodic events
           - Health episodes (current illness, active treatment): 168-720 (1-4 weeks)
           - Withdrawal periods: match the withdrawal duration
           - Permanent facts (chronic conditions, allergies, preferences): null
        
        IMPORTANT: Pay special attention to:
        - Animal health conditions and treatments
        - Vaccination schedules and due dates
        - Medication withdrawal periods
        - Follow-up appointments
        - Disease symptoms and diagnoses
        - Animal-specific health history
        - User's preferred tools and workflows (e.g., "User prefers to set reminders for vaccinations")
        - How user interacts with the assistant (e.g., "User often asks about health records by animal name")
        
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
        
        response = await self.client.aio.models.generate_content(model=self.model, contents=prompt)
        try:
            text = response.text
            start = text.find('[')
            end = text.rfind(']') + 1
            if start != -1 and end > start:
                return json.loads(text[start:end])
        except json.JSONDecodeError:
            pass
        return []

extract = None

def get_extraction_service():
    global extract
    settings = get_settings()
    if extract is None:
        extract = ExtractionService(api_key=settings.gemini_api_key)
    return extract

# Test this class.
# if __name__ == "__main__":
#     import asyncio
#     async def main():
#         settings = get_settings()
#         extraction_service = ExtractionService(api_key=settings.gemini_api_key)
        
#         content = """The farm's cows prefer grazing in the eastern pasture during summer. 
#         Last week, there was a mild outbreak of mastitis among the dairy cows."""
        
#         context = """Farm location: Midwest USA. Main activities: Dairy farming and crop cultivation."""
        
#         memories = await extraction_service.extract_memories(content, context)
#         print("Extracted Memories:", memories)
#     asyncio.run(main())