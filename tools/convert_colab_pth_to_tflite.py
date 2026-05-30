"""
Load torchvision MobileNetV3-Large weights from colab.pth and export float32 TFLite.

Requires: torch, torchvision, tensorflow, onnx, onnx2tf, onnx_graphsurgeon (pulled by onnx2tf)

  pip install onnx onnx2tf tensorflow

Run from repo root:
  python tools/convert_colab_pth_to_tflite.py

Output: assets/models/variety.tflite (overwrites; back up first if needed)
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

import numpy as np
import tensorflow as tf
import torch
import torchvision.models as models


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def load_mobilenet_v3_large_3class(pth: Path) -> torch.nn.Module:
    m = models.mobilenet_v3_large(weights=None)
    m.classifier[3] = torch.nn.Linear(m.classifier[3].in_features, 3)
    try:
        state = torch.load(pth, map_location="cpu", weights_only=True)
    except TypeError:
        state = torch.load(pth, map_location="cpu")
    if not isinstance(state, dict):
        raise ValueError("Expected a state_dict in the .pth file")
    m.load_state_dict(state, strict=True)
    m.eval()
    return m


def export_onnx(model: torch.nn.Module, onnx_path: Path) -> None:
    dummy = torch.randn(1, 3, 224, 224, dtype=torch.float32)
    torch.onnx.export(
        model,
        dummy,
        str(onnx_path),
        input_names=["input"],
        output_names=["output"],
        opset_version=17,
        dynamo=False,
    )


def _ensure_onnx2tf_calibration_npy(cwd: Path) -> None:
    """onnx2tf downloads a sample .npy; a broken partial file makes np.load fail."""
    name = "calibration_image_sample_data_20x128x128x3_float32.npy"
    path = cwd / name
    if path.is_file():
        try:
            np.load(path, allow_pickle=False)
            return
        except Exception:
            path.unlink(missing_ok=True)
    x = np.random.default_rng(0).random((20, 128, 128, 3), dtype=np.float32)
    np.save(str(path), x)


def onnx_to_saved_model(onnx_path: Path, out_dir: Path, work_cwd: Path) -> None:
    try:
        from onnx2tf import convert as onnx2tf_convert
    except ImportError as e:
        raise SystemExit(
            "Missing onnx2tf. Install with: pip install onnx2tf onnx\n" + str(e)
        ) from e
    out_dir.mkdir(parents=True, exist_ok=True)
    work_cwd.mkdir(parents=True, exist_ok=True)
    _ensure_onnx2tf_calibration_npy(work_cwd)
    prev = Path.cwd()
    try:
        import os

        os.chdir(work_cwd)
        onnx2tf_convert(
            input_onnx_file_path=str(onnx_path.resolve()),
            output_folder_path=str(out_dir.resolve()),
            copy_onnx_input_output_names_to_tflite=True,
            non_verbose=True,
        )
    finally:
        os.chdir(prev)


def saved_model_to_tflite(saved_model_dir: Path, tflite_path: Path) -> None:
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter.optimizations = []
    tflite_model = converter.convert()
    tflite_path.parent.mkdir(parents=True, exist_ok=True)
    tflite_path.write_bytes(tflite_model)


def print_io(tflite_path: Path) -> None:
    interp = tf.lite.Interpreter(model_path=str(tflite_path))
    interp.allocate_tensors()
    print("--- TFLite I/O ---")
    for d in interp.get_input_details():
        print("INPUT ", d["name"], d["shape"], d["dtype"])
    for d in interp.get_output_details():
        print("OUTPUT", d["name"], d["shape"], d["dtype"])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--pth",
        type=Path,
        default=_repo_root() / "colab.pth",
        help="Path to PyTorch state_dict (.pth)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=_repo_root() / "assets" / "models" / "variety.tflite",
        help="Output .tflite path",
    )
    parser.add_argument("--keep-temp", action="store_true", help="Keep onnx/ and saved_model/")
    args = parser.parse_args()

    root = _repo_root()
    work = root / "tools" / "_tflite_build"
    work.mkdir(parents=True, exist_ok=True)
    onnx_p = work / "mobilenet_v3.onnx"
    sm_dir = work / "saved_model"

    if not args.pth.is_file():
        print(f"Not found: {args.pth}", file=sys.stderr)
        sys.exit(1)

    print("Loading PyTorch weights…")
    net = load_mobilenet_v3_large_3class(args.pth)

    print("Exporting ONNX…")
    export_onnx(net, onnx_p)

    if sm_dir.exists():
        shutil.rmtree(sm_dir)
    print("ONNX -> TensorFlow SavedModel (onnx2tf)…")
    onnx_to_saved_model(onnx_p, sm_dir, work)

    print("SavedModel -> TFLite float32…")
    saved_model_to_tflite(sm_dir, args.out)

    print(f"Wrote: {args.out}")
    print_io(args.out)

    if not args.keep_temp:
        shutil.rmtree(work, ignore_errors=True)

    print(
        "\nNote: PyTorch ImageNet preprocessing is usually "
        "input in [0,1] (or normalized). Your Flutter app currently feeds "
        "0–255 floats; if accuracy is off, match training preprocessing "
        "(e.g. divide by 255 in Dart or add Rescaling in the TF graph)."
    )


if __name__ == "__main__":
    main()
