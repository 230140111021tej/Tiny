import csv
import math
from pathlib import Path
from collections import Counter, defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(r"D:\FPGA_EdgeAI\cnn_baseline\tiny_cnn")
CSV_FILE = ROOT / "validation" / "results" / "mnist10000_results_20261020_122444.csv"
OUT = ROOT / "docs" / "figures"
OUT.mkdir(parents=True, exist_ok=True)

if not CSV_FILE.exists():
    raise FileNotFoundError(f"Validation CSV not found: {CSV_FILE}")

with CSV_FILE.open("r", newline="", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

if not rows:
    raise RuntimeError("The validation CSV contains no rows.")

print("CSV columns:", list(rows[0].keys()))

def get_value(row, *names):
    for name in names:
        if name in row and row[name] is not None:
            return row[name].strip()
    return ""

def parse_label(value):
    try:
        n = int(value)
        return n if 0 <= n <= 9 else None
    except (ValueError, TypeError):
        return None

received = []
for r in rows:
    true_label = parse_label(get_value(r, "TrueLabel", "True_Label"))
    pred_label = parse_label(get_value(r, "PredictedLabel", "Predicted_Label"))
    if true_label is not None and pred_label is not None:
        received.append((true_label, pred_label, r))

if not received:
    raise RuntimeError(
        "Could not find received predictions. Check the CSV column names printed above."
    )

correct = sum(t == p for t, p, _ in received)
accuracy = 100 * correct / len(received)
print(f"Total attempts: {len(rows)}")
print(f"Responses received: {len(received)}")
print(f"Correct: {correct}")
print(f"Accuracy among responses: {accuracy:.2f}%")

# 1. Overall validation summary
fig, ax = plt.subplots(figsize=(8, 4.8))
labels = ["Correct", "Misclassified", "No response"]
counts = [
    correct,
    len(received) - correct,
    len(rows) - len(received)
]
bars = ax.bar(labels, counts)
ax.set_title("TinyCNN FPGA: Full MNIST Test Results")
ax.set_ylabel("Number of images")
ax.bar_label(bars, fmt="%d", padding=3)
ax.set_ylim(0, max(counts) * 1.15 + 1)
fig.tight_layout()
fig.savefig(OUT / "mnist_validation_summary.png", dpi=200)
plt.close(fig)

# 2. Per-digit accuracy
totals = Counter()
hits = Counter()
for t, p, _ in received:
    totals[t] += 1
    if t == p:
        hits[t] += 1

digit_accuracy = [
    100 * hits[d] / totals[d] if totals[d] else 0
    for d in range(10)
]
fig, ax = plt.subplots(figsize=(8, 4.8))
bars = ax.bar(range(10), digit_accuracy)
ax.set_xticks(range(10))
ax.set_xlabel("True digit")
ax.set_ylabel("Accuracy (%)")
ax.set_ylim(0, 100)
ax.set_title("FPGA Accuracy by MNIST Digit")
ax.bar_label(bars, fmt="%.1f", padding=2, fontsize=8)
fig.tight_layout()
fig.savefig(OUT / "per_digit_accuracy.png", dpi=200)
plt.close(fig)

# 3. Confusion matrix
matrix = [[0 for _ in range(10)] for _ in range(10)]
for t, p, _ in received:
    matrix[t][p] += 1

fig, ax = plt.subplots(figsize=(8, 7))
im = ax.imshow(matrix, interpolation="nearest", aspect="equal")
ax.set_title("TinyCNN FPGA Confusion Matrix")
ax.set_xlabel("Predicted digit")
ax.set_ylabel("True digit")
ax.set_xticks(range(10))
ax.set_yticks(range(10))
fig.colorbar(im, ax=ax, label="Image count")
threshold = max(max(line) for line in matrix) / 2
for i in range(10):
    for j in range(10):
        ax.text(
            j, i, str(matrix[i][j]),
            ha="center", va="center", fontsize=7,
            color="white" if matrix[i][j] > threshold else "black"
        )
fig.tight_layout()
fig.savefig(OUT / "confusion_matrix.png", dpi=200)
plt.close(fig)

# 4. Hardware resource usage. Values from the recorded V7 implementation.
# Basys 3 FPGA: Artix-7 XC7A35T.
resources = {
    "LUT": (1986, 20800),
    "Flip-flops": (851, 41600),
    "BRAM tiles": (2, 50),
    "DSP slices": (1, 90),
}
fig, ax = plt.subplots(figsize=(8, 4.8))
names = list(resources.keys())
percentages = [100 * used / capacity for used, capacity in resources.values()]
bars = ax.bar(names, percentages)
ax.set_ylabel("Device resource used (%)")
ax.set_title("TinyCNN V7: FPGA Resource Utilization")
ax.bar_label(
    bars,
    labels=[
        f"{resources[n][0]} / {resources[n][1]}\n({p:.2f}%)"
        for n, p in zip(names, percentages)
    ],
    padding=3,
    fontsize=8
)
ax.set_ylim(0, max(percentages) * 1.35 + 0.5)
fig.tight_layout()
fig.savefig(OUT / "resource_utilization.png", dpi=200)
plt.close(fig)

# 5. Architecture diagram
fig, ax = plt.subplots(figsize=(13, 3.8))
ax.set_xlim(0, 13)
ax.set_ylim(0, 4)
ax.axis("off")

blocks = [
    (0.2, 1.2, 1.5, 1.4, "28×28 image\n784 U8 pixels"),
    (2.0, 1.2, 1.6, 1.4, "3×3 convolution\n1 → 4 filters"),
    (3.9, 1.2, 1.2, 1.4, "ReLU"),
    (5.4, 1.2, 1.6, 1.4, "2×2 max pool\nstride 2"),
    (7.3, 1.2, 1.5, 1.4, "676 features"),
    (9.1, 1.2, 1.7, 1.4, "Fully connected\n676 → 10"),
    (11.1, 1.2, 1.6, 1.4, "Predicted digit\n0–9"),
]
for x, y, w, h, label in blocks:
    rect = plt.Rectangle(
        (x, y), w, h, facecolor="white",
        edgecolor="black", linewidth=1.4
    )
    ax.add_patch(rect)
    ax.text(x + w/2, y + h/2, label, ha="center", va="center", fontsize=9)

for i in range(len(blocks) - 1):
    x, y, w, h, _ = blocks[i]
    nx, ny, nw, nh, _ = blocks[i + 1]
    ax.annotate(
        "", xy=(nx - 0.05, ny + nh/2),
        xytext=(x + w + 0.05, y + h/2),
        arrowprops=dict(arrowstyle="->", linewidth=1.3)
    )

ax.text(
    6.5, 3.45,
    "TinyCNN FPGA Inference Pipeline",
    ha="center", va="center", fontsize=15, fontweight="bold"
)
ax.text(
    6.5, 0.45,
    "INT8 weights • U8 activations • INT32 accumulators • Fixed-point requantization",
    ha="center", va="center", fontsize=9
)
fig.tight_layout()
fig.savefig(OUT / "tinycnn_architecture.png", dpi=200, bbox_inches="tight")
plt.close(fig)

print("\nGenerated figures:")
for p in sorted(OUT.glob("*.png")):
    print(f"{p.name} ({p.stat().st_size:,} bytes)")
print(f"\nOutput directory: {OUT}")
