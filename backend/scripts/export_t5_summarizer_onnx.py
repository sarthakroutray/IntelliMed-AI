"""Export the Falconsai medical T5 summarizer to ONNX (encoder + decoder).

The backend `medical_summarize_service` uses this exact checkpoint
(`Falconsai/medical_summarization`, T5-small 60M) to turn raw OCR text into
`{medical_summary, key_findings, ...}` for non-prescription documents. This
script exports both halves so the app's OnnxSlmRuntime can run the same
standardizer on-device (encoder once per input, decoder autoregressively).

Usage:
    python backend/scripts/export_t5_summarizer_onnx.py [--out-dir dir]

Outputs:
    <out-dir>/t5_encoder.onnx      (input_ids, attention_mask -> hidden states)
    <out-dir>/t5_decoder.onnx      (input_ids, encoder_hidden -> logits)
    <out-dir>/tokenizer.json       (via transformers save_pretrained)
    <out-dir>/manifest.json        (model id, param count, parity numbers)

Step 2 (quantize) runs separately with onnxruntime quantization tooling.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

MODEL_ID = 'Falconsai/medical_summarization'


class _EncoderWrapper(__import__('torch').nn.Module):
    def __init__(self, model):
        super().__init__()
        self.encoder = model.encoder

    def forward(self, input_ids, attention_mask):
        return self.encoder(
            input_ids=input_ids, attention_mask=attention_mask
        ).last_hidden_state


class _DecoderWrapper(__import__('torch').nn.Module):
    def __init__(self, model):
        super().__init__()
        self.decoder = model.decoder
        self.lm_head = model.lm_head

    def forward(self, input_ids, encoder_hidden_states, encoder_attention_mask):
        out = self.decoder(
            input_ids=input_ids,
            encoder_hidden_states=encoder_hidden_states,
            encoder_attention_mask=encoder_attention_mask,
        ).last_hidden_state
        return self.lm_head(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--out-dir',
        default=str(BACKEND_DIR / 'models' / 't5_summarizer_onnx'),
        help='Destination directory for encoder/decoder/tokenizer.',
    )
    parser.add_argument('--opset', type=int, default=17)
    args = parser.parse_args()

    import torch
    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

    print(f'Downloading {MODEL_ID} ...')
    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModelForSeq2SeqLM.from_pretrained(MODEL_ID)
    model.eval()
    n_params = sum(p.numel() for p in model.parameters())
    print(f'Model: {type(model).__name__} | params: {n_params} | vocab: {tok.vocab_size}')

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    enc_path = out_dir / 't5_encoder.onnx'
    dec_path = out_dir / 't5_decoder.onnx'

    dummy_ids = torch.ones(1, 32, dtype=torch.long)
    dummy_mask = torch.ones(1, 32, dtype=torch.long)

    print('Exporting encoder ...')
    torch.onnx.export(
        _EncoderWrapper(model),
        (dummy_ids, dummy_mask),
        str(enc_path),
        input_names=['input_ids', 'attention_mask'],
        output_names=['hidden_states'],
        dynamic_axes={
            'input_ids': {0: 'batch', 1: 'seq'},
            'attention_mask': {0: 'batch', 1: 'seq'},
            'hidden_states': {0: 'batch', 1: 'seq'},
        },
        opset_version=args.opset,
    )

    print('Exporting decoder ...')
    dummy_dec_ids = torch.ones(1, 1, dtype=torch.long)
    dummy_hidden = torch.randn(1, 32, model.config.d_model)
    torch.onnx.export(
        _DecoderWrapper(model),
        (dummy_dec_ids, dummy_hidden, dummy_mask),
        str(dec_path),
        input_names=['input_ids', 'encoder_hidden_states', 'encoder_attention_mask'],
        output_names=['logits'],
        dynamic_axes={
            'input_ids': {0: 'batch', 1: 'seq'},
            'encoder_hidden_states': {0: 'batch', 1: 'seq'},
            'encoder_attention_mask': {0: 'batch', 1: 'seq'},
            'logits': {0: 'batch', 1: 'seq'},
        },
        opset_version=args.opset,
    )

    print('Saving tokenizer ...')
    tok.save_pretrained(str(out_dir))

    import onnx

    for p in (enc_path, dec_path):
        onnx.checker.check_model(str(p))

    # Parity check: HF generate vs manual encoder+decoder greedy loop (5 tokens).
    print('Parity check (5-token greedy prefix) ...')
    sample = 'summarize: The patient was prescribed Amoxicillin 500 mg twice daily for 7 days.'
    enc = tok(sample, max_length=128, truncation=True, return_tensors='pt')
    import onnxruntime as ort

    enc_sess = ort.InferenceSession(str(enc_path), providers=['CPUExecutionProvider'])
    dec_sess = ort.InferenceSession(str(dec_path), providers=['CPUExecutionProvider'])
    hidden = enc_sess.run(None, {
        'input_ids': enc.input_ids.numpy().astype('int64'),
        'attention_mask': enc.attention_mask.numpy().astype('int64'),
    })[0]

    with torch.no_grad():
        hf_ids = model.generate(enc.input_ids, max_length=enc.input_ids.shape[1] + 5, min_length=5)

    import numpy as np

    dec_ids = np.array([[model.config.decoder_start_token_id]], dtype='int64')
    for _ in range(5):
        logits = dec_sess.run(None, {
            'input_ids': dec_ids,
            'encoder_hidden_states': hidden.astype('float32'),
            'encoder_attention_mask': enc.attention_mask.numpy().astype('int64'),
        })[0]
        dec_ids = np.concatenate([dec_ids, logits[:, -1:].argmax(-1).astype('int64')], axis=1)

    hf_prefix = hf_ids[0, : dec_ids.shape[1]].tolist()
    onnx_prefix = dec_ids[0].tolist()
    match = hf_prefix == onnx_prefix
    print(f'  HF prefix:   {hf_prefix}')
    print(f'  ONNX prefix: {onnx_prefix}')
    print(f'  match: {match}')

    manifest = {
        'model_id': MODEL_ID,
        'params': n_params,
        'opset': args.opset,
        'files': ['t5_encoder.onnx', 't5_decoder.onnx', 'tokenizer.json'],
        'parity_5tok_match': match,
        'role': 'OCR text standardizer -> {medical_summary, key_findings} for non-prescription docs',
    }
    (out_dir / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    print(f'Done: {out_dir}')
    if not match:
        print('WARNING: parity mismatch — do not ship without investigating')
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
