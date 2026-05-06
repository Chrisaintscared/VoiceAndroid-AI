from __future__ import annotations

import asyncio
import base64
import logging
import traceback

import httpx
import numpy as np
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.database import (
    get_attendance_logs,
    get_voice_profile,
    has_attendance_today,
    is_enrolled,
    save_attendance,
)
from app.security import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(tags=["attendance"])

# ── Tuning constants ──────────────────────────────────────────────────────────
SIMILARITY_THRESHOLD = 0.85
MODAL_ENDPOINT_URL = "https://chrisaintscared--voice-verification-voiceverifier-extrac-e0e52a.modal.run/"

# ── Modal call ────────────────────────────────────────────────────────────────

async def _get_embedding_from_modal(audio_bytes: bytes) -> np.ndarray:
    """Send audio to Modal, poll until result is ready."""
    audio_b64 = base64.b64encode(audio_bytes).decode("utf-8")

    async with httpx.AsyncClient(timeout=180.0, follow_redirects=False) as client:
        # Initial POST
        response = await client.post(
            MODAL_ENDPOINT_URL,
            json={"audio_b64": audio_b64},
        )

        # Poll on 303 redirects
        max_polls = 40  # 40 x 5s = 200s max
        polls = 0
        while response.status_code == 303 and polls < max_polls:
            poll_url = response.headers.get("location")
            if not poll_url:
                raise HTTPException(status_code=502, detail="Modal redirect missing location header.")
            logger.info("Modal polling attempt %d: %s", polls + 1, poll_url)
            await asyncio.sleep(5)
            response = await client.get(poll_url)
            polls += 1

        if response.status_code == 303:
            raise HTTPException(status_code=504, detail="Voice processing timed out. Please try again.")

        if response.status_code != 200:
            logger.error("Modal error %d: %s", response.status_code, response.text)
            raise HTTPException(status_code=502, detail="Voice service error.")

    data = response.json()
    if "error" in data:
        raise HTTPException(status_code=400, detail=data["error"])

    return np.array(data["embedding"])


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/mark")
async def mark_attendance(
    class_id: int,
    audio: UploadFile = File(...),
    user=Depends(get_current_user),
):
    if not is_enrolled(class_id, user["id"]):
        raise HTTPException(
            status_code=403, detail="You are not enrolled in this class."
        )

    if has_attendance_today(class_id, user["id"]):
        raise HTTPException(
            status_code=409, detail="Attendance already marked for today."
        )

    stored = get_voice_profile(user["id"])
    if not stored:
        raise HTTPException(
            status_code=400,
            detail="No voice profile found. Please enroll your voice first.",
        )

    try:
        audio_bytes = await audio.read()
        logger.info("Audio received: %d bytes for user_id=%s", len(audio_bytes), user["id"])

        live_emb = await _get_embedding_from_modal(audio_bytes)

        stored_emb = np.array(stored["embedding"])

        logger.info("Live embedding norm:   %.6f", float(np.linalg.norm(live_emb)))
        logger.info("Stored embedding norm: %.6f", float(np.linalg.norm(stored_emb)))

        similarity = float(np.dot(live_emb, stored_emb))

        logger.info(
            "Voice similarity score: %.4f (threshold: %.2f) user_id=%s",
            similarity, SIMILARITY_THRESHOLD, user["id"],
        )

        if similarity < SIMILARITY_THRESHOLD:
            logger.info(
                "REJECTED: score %.4f below threshold %.2f for user_id=%s",
                similarity, SIMILARITY_THRESHOLD, user["id"],
            )
            raise HTTPException(
                status_code=401,
                detail=f"Voice not recognised (score: {similarity:.2f}). Try again.",
            )

        logger.info(
            "ACCEPTED: score %.4f for user_id=%s class_id=%s",
            similarity, user["id"], class_id,
        )

        save_attendance(
            user_id=user["id"],
            user_name=user["name"],
            class_id=class_id,
        )

        return {"status": "success", "confidence": round(similarity * 100, 2)}

    except HTTPException:
        raise
    except Exception:
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="Internal server error.")


@router.get("/logs")
async def get_logs(
    class_id: int | None = None,
    user=Depends(get_current_user),
):
    try:
        logs = get_attendance_logs(user_id=user["id"], class_id=class_id)
        return {"logs": logs}
    except Exception:
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="Failed to load attendance logs.")


@router.get("/test")
async def test_connection():
    return {"status": "ok"}