import asyncio
import time
from typing import AsyncGenerator, Dict, Any, Optional, List
from pydantic import BaseModel

class AudioChunk(BaseModel):
    sequence_id: int
    audio_base64: str
    is_final: bool
    text_snippet: Optional[str] = None
    duration_ms: int = 250

class VoicePipelineMetrics(BaseModel):
    stt_latency_ms: float
    llm_ttft_ms: float # Time to first token
    tts_first_chunk_ms: float # Time to first audio chunk
    total_ttfa_ms: float # Total Time to First Audio Byte
    tokens_generated: int

class VoicePipelineSession:
    """
    Manages an active real-time two-way voice turn.
    Coordinates streaming STT -> streaming LLM -> streaming TTS with instant barge-in support.
    """
    def __init__(self, session_id: str, companion_name: str = "Nuvin"):
        self.session_id = session_id
        self.companion_name = companion_name
        self.current_seq_id = 0
        self.is_interrupted = False
        self.last_played_seq = 0

    def interrupt_barge_in(self, last_played_seq: int) -> Dict[str, Any]:
        """
        Instant client-side interruption handler.
        Cancels downstream audio synthesis immediately and drops remaining playback queue.
        """
        self.is_interrupted = True
        self.last_played_seq = last_played_seq
        return {
            "status": "barge_in_acknowledged",
            "truncated_at_seq": last_played_seq,
            "session_id": self.session_id
        }

    async def simulate_streaming_turn(
        self,
        user_transcript: str,
        system_prompt: str,
        response_text: str
    ) -> AsyncGenerator[AudioChunk, None]:
        """
        Simulates the low-latency streaming pipeline:
        Chunks response into conversational phrases and streams audio packets.
        """
        self.is_interrupted = False
        self.current_seq_id = 0
        # Split into natural sentence/clause chunks for TTS
        phrases = [p.strip() for p in response_text.replace(".", ".|").replace("?", "?|").replace("!", "!|").split("|") if p.strip()]
        
        for i, phrase in enumerate(phrases):
            if self.is_interrupted:
                break
                
            self.current_seq_id += 1
            # Mock low-latency audio chunk (PCM/Opus representation)
            chunk = AudioChunk(
                sequence_id=self.current_seq_id,
                audio_base64=f"mock_audio_pcm_bytes_{self.current_seq_id}",
                is_final=(i == len(phrases) - 1),
                text_snippet=phrase,
                duration_ms=len(phrase) * 60
            )
            yield chunk
            # Realistic streaming chunk cadence (50ms gap)
            await asyncio.sleep(0.05)
