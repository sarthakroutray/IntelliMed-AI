"""Export the pneumonia ResNet50 checkpoint to ONNX (step 1 of the TFLite bridge).

Rebuilds the exact head from backend/services.py::_load_pneumonia_model
(ResNet50 + Dropout(0.3) + Linear(2048 -> 3)), loads the fine-tuned
`best_model_optimized.pkl` state dict, and exports a [1,3,224,224] ONNX graph.

Usage:
    python backend/scripts/export_pneumonia_onnx.py [--out path] [--opset N]

Step 2 (ONNX -> quantized .tflite) runs where TF is available:
    onnx2tf -i <out.onnx> -o <saved_model_dir>  (needs onnx2tf + TF)
    # then TFLiteConverter with dynamic-range quantization.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

CLASS_NAMES = ['Normal', 'Bacterial Pneumonia', 'Viral Pneumonia']


def build_model(state_dict_path: Path):
    import torch
    from torch import nn
    from torchvision import models
    from torchvision.models import ResNet50_Weights

    model = models.resnet50(weights=None)
    model.fc = nn.Sequential(
        nn.Dropout(p=0.3),
        nn.Linear(model.fc.in_features, len(CLASS_NAMES)),
    )
    state = torch.load(str(state_dict_path), map_location='cpu')
    model.load_state_dict(state)
    model.eval()
    return model


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--ckpt',
        default=str(BACKEND_DIR / 'models' / 'best_model_optimized.pkl'),
        help='Fine-tuned state-dict checkpoint.',
    )
    parser.add_argument(
        '--out',
        default=str(BACKEND_DIR / 'models' / 'pneumonia_resnet50.onnx'),
        help='Destination ONNX path.',
    )
    parser.add_argument('--opset', type=int, default=17)
    args = parser.parse_args()

    import torch

    ckpt = Path(args.ckpt)
    if not ckpt.exists():
        print(f'Checkpoint not found: {ckpt}')
        return 1

    model = build_model(ckpt)
    dummy = torch.randn(1, 3, 224, 224)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    torch.onnx.export(
        model,
        dummy,
        str(out),
        input_names=['input'],
        output_names=['logits'],
        dynamic_axes={'input': {0: 'batch'}, 'logits': {0: 'batch'}},
        opset_version=args.opset,
    )

    import onnx

    onnx_model = onnx.load(str(out))
    onnx.checker.check_model(onnx_model)
    print(f'Exported {out} ({out.stat().st_size / 1e6:.1f} MB), opset {args.opset}')
    print(f'Classes: {CLASS_NAMES}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
