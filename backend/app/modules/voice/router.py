from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException
from typing import Dict, Any, Optional
import json
import time

from backend.app.modules.agent.orchestrator import AgentOrchestrator, AgentTurnRequest, AgentTurnResponse
from backend.app.modules.voice.pipeline import VoicePipelineSession, AudioChunk

router = APIRouter(tags=["Real-Time Voice & Chat Gateway"])

@router.post("/api/v1/agent/chat", response_model=AgentTurnResponse)
@router.post("/agent/chat", response_model=AgentTurnResponse)
async def process_chat_turn(req: AgentTurnRequest):
    """
    Mode 2: Chat with OpenUI HTTP endpoint.
    Returns spoken text, OpenUI cards (if triggered), and safety status.
    """
    return await AgentOrchestrator.process_turn(req)

@router.websocket("/api/v1/voice/stream/{user_id}")
async def voice_streaming_endpoint(websocket: WebSocket, user_id: str):
    """
    Mode 1 & Mode 3: Real-Time Full-Duplex Voice WebSocket.
    Supports audio streaming, OpenUI card events, and instant client-side barge-in.
    """
    await websocket.accept()
    session = VoicePipelineSession(session_id=user_id)

    try:
        while True:
            raw_data = await websocket.receive_text()
            msg = json.loads(raw_data)
            msg_type = msg.get("type")

            # 1. Handle Barge-In Interruption
            if msg_type == "barge_in":
                last_played = msg.get("last_played_seq", 0)
                ack = session.interrupt_barge_in(last_played)
                await websocket.send_json({"type": "barge_in_ack", **ack})
                continue

            # 2. Handle User Transcript / Turn
            if msg_type == "user_turn":
                text = msg.get("text", "")
                locale = msg.get("locale")
                start_time = time.time()

                turn_req = AgentTurnRequest(user_id=user_id, message=text, locale=locale, channel="voice")
                turn_res = await AgentOrchestrator.process_turn(turn_req)

                ttfa_latency_ms = (time.time() - start_time) * 1000

                # Send OpenUI Card if generated
                if turn_res.open_ui_card:
                    await websocket.send_json({
                        "type": "open_ui_card",
                        "card": turn_res.open_ui_card
                    })

                # Stream Audio Chunks
                async for chunk in session.simulate_streaming_turn(
                    user_transcript=text,
                    system_prompt="",
                    response_text=turn_res.spoken_response
                ):
                    await websocket.send_json({
                        "type": "audio_chunk",
                        "sequence_id": chunk.sequence_id,
                        "audio": chunk.audio_base64,
                        "text": chunk.text_snippet,
                        "is_final": chunk.is_final
                    })

                # Send Turn Completion
                await websocket.send_json({
                    "type": "turn_complete",
                    "full_text": turn_res.spoken_response,
                    "metrics": {
                        "ttfa_ms": round(ttfa_latency_ms, 2),
                        "tts_rate": turn_res.tts_rate,
                        "vad_pause_tolerance_ms": turn_res.vad_pause_tolerance_ms
                    }
                })

    except WebSocketDisconnect:
        pass
    except Exception as e:
        await websocket.close()
