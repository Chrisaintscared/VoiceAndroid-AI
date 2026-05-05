from __future__ import annotations

import base64
import logging
import traceback

import httpx
import numpy as np
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.database import save_voice_profile
from app.security import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(tags=["voice"])

MODAL_ENDPOINT_URL = "https://chrisaintscared--voice-verification-voiceverifier-extrac-e0e52a.modal.run"

async def _get_embedding_from_modal(audio_bytes: bytes) -> np.ndarray:
    audio_b64 = base64.b64encode(audio_bytes).decode("utf-8")

    async with httpx.AsyncClient(timeout=60.0) as client:
        try:
            response = await client.post(
                MODAL_ENDPOINT_URL,
                json={"audio_b64": audio_b64},
            )
            response.raise_for_status()
        except httpx.TimeoutException:
            raise HTTPException(status_code=504, detail="Voice processing timed out. Please try again.")
        except httpx.HTTPStatusError as e:
            logger.error("Modal returned error: %s", e.response.text)
            raise HTTPException(status_code=502, detail="Voice service error.")

    data = response.json()

    if "error" in data:
        raise HTTPException(status_code=400, detail=data["error"])

    return np.array(data["embedding"])


@router.post("/enroll-voice")
async def enroll_voice(
    voice: UploadFile = File(...),
    user=Depends(get_current_user),
):
    try:
        audio_bytes = await voice.read()
        logger.info("Enrollment audio received: %d bytes for user_id=%s", len(audio_bytes), user["id"])

        embedding = await _get_embedding_from_modal(audio_bytes)

        save_voice_profile(
            user_id=user["id"],
            embedding=embedding.tolist(),
        )

        logger.info("Voice enrolled successfully for user_id=%s", user["id"])
        return {"status": "enrolled"}

    except HTTPException:
        raise
    except Exception:
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="Enrollment failed.")