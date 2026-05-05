import io
import modal

app = modal.App("voice-verification")

image = (
    modal.Image.debian_slim()
 .pip_install(
        "speechbrain==1.0.0",
        "torch==2.2.2",
        "torchaudio==2.2.2",
        "pydub==0.25.1",
        "numpy==1.26.4",
        "fastapi[standard]",
    )
)

@app.function(
    image=image,
    cpu=1,
    memory=1024,
    timeout=60,
    # Keeps the container warm for 5 minutes after last request
    # so students checking in back-to-back don't hit cold starts
    scaledown_window=300,
)
@modal.fastapi_endpoint(method="POST")
async def extract_embedding(item: dict):
    """
    Accepts:  { "audio_b64": "<base64 encoded audio bytes>" }
    Returns:  { "embedding": [...], "rms_energy": 0.123 }
    """
    import base64
    import gc

    import numpy as np
    import torch
    from pydub import AudioSegment
    from speechbrain.inference.speaker import SpeakerRecognition

    TARGET_SR = 16_000
    ENERGY_SILENCE_THRESH = 0.02

    # Load model (cached across warm invocations)
    verifier = SpeakerRecognition.from_hparams(
        source="speechbrain/spkrec-ecapa-voxceleb",
        savedir="/tmp/pretrained_models/spkrec-ecapa",
        run_opts={"device": "cpu"},
    )
    for param in verifier.mods.parameters():
        param.requires_grad_(False)

    audio_bytes = base64.b64decode(item["audio_b64"])

    seg = AudioSegment.from_file(io.BytesIO(audio_bytes))
    seg = seg.set_channels(1).set_frame_rate(TARGET_SR).set_sample_width(2)
    samples = (
        np.frombuffer(seg.raw_data, dtype=np.int16).astype(np.float32) / 32768.0
    )

    rms_energy = float(np.sqrt(np.mean(samples ** 2)))
    if rms_energy < ENERGY_SILENCE_THRESH:
        return {"error": "Audio is too quiet. Please speak more clearly.", "rms_energy": rms_energy}

    tensor_input = torch.tensor(samples).unsqueeze(0)
    tensor_len = torch.tensor([1.0])

    with torch.no_grad():
        embedding = verifier.encode_batch(tensor_input, tensor_len)

    emb_np = embedding.squeeze().cpu().numpy().copy()
    del tensor_input, tensor_len, embedding
    gc.collect()

    norm = float(np.linalg.norm(emb_np))
    if norm == 0:
        return {"error": "Could not extract a valid voice embedding."}

    emb_normalised = emb_np / norm

    return {
        "embedding": emb_normalised.tolist(),
        "rms_energy": rms_energy,
    }