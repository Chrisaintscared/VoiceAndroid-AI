import io
import modal

app = modal.App("voice-verification")

image = (
    modal.Image.debian_slim()
    .pip_install(
        "huggingface_hub==0.23.4",
        "speechbrain==1.0.2",
        "torch==2.2.2",
        "torchaudio==2.2.2",
        "pydub==0.25.1",
        "numpy==1.26.4",
        "fastapi[standard]",
        "requests",
    )
    .run_commands(
        "python -c \""
        "from speechbrain.inference.speaker import SpeakerRecognition; "
        "SpeakerRecognition.from_hparams("
        "source='speechbrain/spkrec-ecapa-voxceleb', "
        "savedir='/opt/pretrained_models/spkrec-ecapa', "
        "run_opts={'device': 'cpu'}"
        ")\""
    )
)

with image.imports():
    import base64
    import gc
    import numpy as np
    import torch
    from pydub import AudioSegment
    from speechbrain.inference.speaker import SpeakerRecognition

@app.cls(
    image=image,
    cpu=1,
    memory=2048,
    timeout=120,
    scaledown_window=60,
)
class VoiceVerifier:

    @modal.enter()
    def load_model(self):
        """Runs once when the container starts — model stays in memory."""
        self.verifier = SpeakerRecognition.from_hparams(
            source="speechbrain/spkrec-ecapa-voxceleb",
            savedir="/opt/pretrained_models/spkrec-ecapa",
            run_opts={"device": "cpu"},
        )
        for param in self.verifier.mods.parameters():
            param.requires_grad_(False)

    @modal.fastapi_endpoint(method="POST")
    async def extract_embedding(self, item: dict):
        """
        Accepts:  { "audio_b64": "<base64 encoded audio bytes>" }
        Returns:  { "embedding": [...], "rms_energy": 0.123 }
        """
        TARGET_SR = 16_000
        ENERGY_SILENCE_THRESH = 0.02

        audio_bytes = base64.b64decode(item["audio_b64"])
        seg = AudioSegment.from_file(io.BytesIO(audio_bytes))
        seg = seg.set_channels(1).set_frame_rate(TARGET_SR).set_sample_width(2)

        samples = (
            np.frombuffer(seg.raw_data, dtype=np.int16).astype(np.float32) / 32768.0
        )

        rms_energy = float(np.sqrt(np.mean(samples ** 2)))
        if rms_energy < ENERGY_SILENCE_THRESH:
            return {
                "error": "Audio is too quiet. Please speak more clearly.",
                "rms_energy": rms_energy,
            }

        tensor_input = torch.tensor(samples).unsqueeze(0)
        tensor_len = torch.tensor([1.0])

        with torch.no_grad():
            embedding = self.verifier.encode_batch(tensor_input, tensor_len)

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