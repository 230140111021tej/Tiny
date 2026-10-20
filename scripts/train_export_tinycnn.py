import argparse
import gzip
import json
import struct
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, TensorDataset

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "MNIST" / "raw"
OUT = ROOT / "tiny_cnn"
ROM = OUT / "rom"
MODEL_DIR = OUT / "model"
REPORTS = OUT / "reports"


def load_idx(name, expected_magic):
    path = DATA / name
    if not path.exists():
        path = DATA / (name + ".gz")
    if not path.exists():
        raise FileNotFoundError(
            f"MNIST file not found: {DATA / name} or {DATA / (name + '.gz')}"
        )

    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rb") as f:
        magic = struct.unpack(">I", f.read(4))[0]
        if magic != expected_magic:
            raise ValueError(f"Unexpected IDX magic {magic} in {path}")

        if expected_magic == 2051:
            count, rows, cols = struct.unpack(">III", f.read(12))
            raw = f.read()
            if len(raw) != count * rows * cols:
                raise ValueError(f"Invalid image file length: {path}")
            return torch.frombuffer(
                bytearray(raw), dtype=torch.uint8
            ).clone().reshape(count, 1, rows, cols)

        count = struct.unpack(">I", f.read(4))[0]
        raw = f.read()
        if len(raw) != count:
            raise ValueError(f"Invalid label file length: {path}")
        return torch.frombuffer(
            bytearray(raw), dtype=torch.uint8
        ).clone()


class TinyCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 4, kernel_size=3, padding=0)
        self.fc1 = nn.Linear(4 * 13 * 13, 10)

    def forward(self, x):
        x = F.relu(self.conv1(x))
        x = F.max_pool2d(x, kernel_size=2, stride=2)
        x = torch.flatten(x, 1)
        return self.fc1(x)


def signed_hex(value, bits):
    return f"{int(value) & ((1 << bits) - 1):0{bits // 4}X}"


def write_mem(path, values, bits):
    with path.open("w", newline="\n") as f:
        for value in values:
            f.write(signed_hex(value, bits) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=5)
    args = parser.parse_args()

    if args.epochs < 1:
        raise ValueError("--epochs must be at least 1")

    torch.manual_seed(2026)
    torch.set_num_threads(2)

    for folder in (ROM, MODEL_DIR, REPORTS):
        folder.mkdir(parents=True, exist_ok=True)

    train_raw = load_idx("train-images-idx3-ubyte", 2051)
    train_y = load_idx("train-labels-idx1-ubyte", 2049).long()
    test_raw = load_idx("t10k-images-idx3-ubyte", 2051)
    test_y = load_idx("t10k-labels-idx1-ubyte", 2049).long()

    if train_raw.shape[1:] != (1, 28, 28):
        raise ValueError(f"Unexpected input shape: {train_raw.shape}")

    train_x = train_raw.float() / 255.0
    test_x = test_raw.float() / 255.0

    loader = DataLoader(
        TensorDataset(train_x, train_y),
        batch_size=128,
        shuffle=True,
        num_workers=0,
    )

    model = TinyCNN()
    optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
    loss_fn = nn.CrossEntropyLoss()

    print(f"Training TinyCNN: {args.epochs} epochs")
    for epoch in range(args.epochs):
        model.train()
        total_loss = 0.0
        correct = 0
        count = 0

        for xb, yb in loader:
            optimizer.zero_grad()
            logits = model(xb)
            loss = loss_fn(logits, yb)
            loss.backward()
            optimizer.step()

            total_loss += loss.item() * len(yb)
            correct += (logits.argmax(1) == yb).sum().item()
            count += len(yb)

        print(
            f"Epoch {epoch + 1}/{args.epochs}: "
            f"loss={total_loss / count:.4f}, "
            f"train_accuracy={100.0 * correct / count:.2f}%"
        )

    model.eval()
    torch.save(model.state_dict(), MODEL_DIR / "tinycnn_float.pt")

    with torch.no_grad():
        float_correct = 0
        for start in range(0, len(test_x), 256):
            logits = model(test_x[start:start + 256])
            float_correct += (
                logits.argmax(1) == test_y[start:start + 256]
            ).sum().item()

    float_accuracy = float_correct / len(test_y)

    # Symmetric signed INT8 quantization for convolution weights.
    w1 = model.conv1.weight.detach().cpu().double()
    b1 = model.conv1.bias.detach().cpu().double()
    sw1 = max(float(w1.abs().max()) / 127.0, 1e-12)
    w1q = torch.round(w1 / sw1).clamp(-127, 127).to(torch.int64)

    # Calibrate the post-ReLU activation range using training images.
    with torch.no_grad():
        max_activation = 0.0
        for start in range(0, min(10000, len(train_x)), 256):
            a = F.relu(model.conv1(train_x[start:start + 256]))
            max_activation = max(
                max_activation, float(a.max())
            )

    if max_activation <= 0:
        raise RuntimeError("Convolution calibration produced no positive activations")

    activation_scale = max_activation / 255.0
    conv_bias_q = torch.round(b1 * 255.0 / sw1).to(torch.int64)

    # Integer multiplier for:
    # activation_u8 = round(accumulator * multiplier / 2**shift)
    shift = 24
    multiplier = int(round(
        (sw1 / (255.0 * activation_scale)) * (1 << shift)
    ))
    if multiplier <= 0:
        raise RuntimeError("Invalid convolution requantization multiplier")

    # Quantize the classifier weights and express its bias in the
    # same scale as the pooled unsigned 8-bit activations.
    w2 = model.fc1.weight.detach().cpu().double()
    b2 = model.fc1.bias.detach().cpu().double()
    sw2 = max(float(w2.abs().max()) / 127.0, 1e-12)
    w2q = torch.round(w2 / sw2).clamp(-127, 127).to(torch.int64)
    fc_bias_q = torch.round(
        b2 / (activation_scale * sw2)
    ).to(torch.int64)

    # Exact integer-domain reference inference. Float64 is used only
    # to calculate integer dot products exactly before converting to int64.
    w1qd = w1q.to(torch.float64)
    w2qd = w2q.to(torch.float64)
    quant_correct = 0
    first_scores = None
    first_pooled = None

    with torch.no_grad():
        for start in range(0, len(test_raw), 128):
            pixels = test_raw[start:start + 128].to(torch.float64)

            conv_acc = F.conv2d(pixels, w1qd).round().to(torch.int64)
            conv_acc += conv_bias_q.reshape(1, 4, 1, 1)
            conv_acc = conv_acc.clamp_min(0)

            # Positive-value round-to-nearest before shifting.
            conv_q = (
                conv_acc * multiplier + (1 << (shift - 1))
            ) >> shift
            conv_q = conv_q.clamp(0, 255)

            pooled = F.max_pool2d(
                conv_q.to(torch.float64), kernel_size=2, stride=2
            ).to(torch.int64)
            flat = pooled.flatten(1)

            scores = F.linear(
                flat.to(torch.float64), w2qd
            ).round().to(torch.int64)
            scores += fc_bias_q.reshape(1, 10)

            predicted = scores.argmax(1)
            quant_correct += (
                predicted == test_y[start:start + 128]
            ).sum().item()

            if start == 0:
                first_scores = scores[0].tolist()
                first_pooled = pooled[0].flatten().tolist()

    quant_accuracy = quant_correct / len(test_y)

    # Export weights in output-channel/neuron-major order.
    write_mem(ROM / "conv1_weights_int8.mem", w1q.flatten().tolist(), 8)
    write_mem(ROM / "conv1_bias_int32.mem", conv_bias_q.tolist(), 32)
    write_mem(ROM / "fc1_weights_int8.mem", w2q.flatten().tolist(), 8)
    write_mem(ROM / "fc1_bias_int32.mem", fc_bias_q.tolist(), 32)

    write_mem(
        ROM / "test_image_u8.mem",
        test_raw[0].flatten().tolist(),
        8,
    )
    write_mem(ROM / "expected_pooled_u8.mem", first_pooled, 8)
    write_mem(ROM / "expected_scores_int32.mem", first_scores, 32)

    (ROM / "conv1_requant.txt").write_text(
        f"multiplier={multiplier}\nshift={shift}\n",
        encoding="utf-8",
    )
    (ROM / "expected_label.txt").write_text(
        f"{int(test_y[0])}\n", encoding="utf-8"
    )

    summary = {
        "architecture": "Conv3x3_1to4_ReLU_MaxPool2x2_FC676to10",
        "input": "28x28 grayscale, unsigned 8-bit pixels",
        "conv_weights": "signed INT8",
        "activation": "unsigned INT8",
        "accumulators": "signed INT32 required",
        "fc_weights": "signed INT8",
        "float_test_accuracy": float_accuracy,
        "quantized_test_accuracy": quant_accuracy,
        "test_images": len(test_y),
        "first_test_label": int(test_y[0]),
        "first_test_prediction": int(torch.tensor(first_scores).argmax()),
        "conv_weight_scale": sw1,
        "activation_scale": activation_scale,
        "fc_weight_scale": sw2,
        "conv_requant_multiplier": multiplier,
        "conv_requant_shift": shift,
        "weight_layout": {
            "conv": "out_channel,in_channel,kernel_y,kernel_x",
            "fc": "output_neuron,input_feature",
        },
    }

    (REPORTS / "model_summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )

    print("\n--- TinyCNN results ---")
    print(f"Float test accuracy:     {100 * float_accuracy:.2f}%")
    print(f"Quantized test accuracy: {100 * quant_accuracy:.2f}%")
    print(f"First test label:        {int(test_y[0])}")
    print(f"First predicted label:   {summary['first_test_prediction']}")
    print(f"First integer scores:    {first_scores}")
    print(f"Artifacts:               {OUT}")
    print(f"Summary:                 {REPORTS / 'model_summary.json'}")


if __name__ == "__main__":
    main()
