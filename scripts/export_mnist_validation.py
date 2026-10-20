import argparse, csv, gzip, struct
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATA = PROJECT_ROOT.parent / "data" / "MNIST" / "raw"
DATA = DEFAULT_DATA
OUT = PROJECT_ROOT / "validation"

def open_idx(name):
    p = DATA / name
    if p.exists():
        return open(p, "rb")
    p = DATA / (name + ".gz")
    if p.exists():
        return gzip.open(p, "rb")
    raise FileNotFoundError(f"Missing {DATA / name} (or .gz). No download was attempted.")

def read_images():
    with open_idx("t10k-images-idx3-ubyte") as f:
        magic, n, rows, cols = struct.unpack(">IIII", f.read(16))
        if magic != 2051 or (rows, cols) != (28, 28):
            raise ValueError(f"Unexpected image IDX header: {magic}, {rows}x{cols}")
        raw = f.read()
    if len(raw) != n * 784:
        raise ValueError("MNIST image file length mismatch")
    return [raw[i*784:(i+1)*784] for i in range(n)]

def read_labels():
    with open_idx("t10k-labels-idx1-ubyte") as f:
        magic, n = struct.unpack(">II", f.read(8))
        if magic != 2049:
            raise ValueError(f"Unexpected label IDX magic: {magic}")
        raw = f.read()
    if len(raw) != n:
        raise ValueError("MNIST label file length mismatch")
    return list(raw)

def export_set(name, images, labels, indices):
    folder = OUT / name
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / "manifest.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["sample_id", "mnist_index", "true_label", "image_file"])
        w.writeheader()
        for sid, idx in enumerate(indices):
            label = labels[idx]
            filename = f"sample_{sid:03d}_label_{label}.mem"
            with (folder / filename).open("w", encoding="ascii", newline="\n") as im:
                im.writelines(f"{v:02X}\n" for v in images[idx])
            w.writerow({"sample_id": sid, "mnist_index": idx, "true_label": label, "image_file": filename})
    print(f"{name}: {len(indices)} images -> {folder}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", choices=["10", "100", "1000", "10000", "both"], default="both")
    ap.add_argument("--data-dir", type=Path, default=DEFAULT_DATA, help="Directory containing MNIST test IDX files")
    args = ap.parse_args()
    global DATA
    DATA = args.data_dir.resolve()
    images, labels = read_images(), read_labels()
    if len(images) != len(labels):
        raise ValueError("Image/label counts differ")

    first = {}
    per_digit = {d: [] for d in range(10)}
    for idx, label in enumerate(labels):
        first.setdefault(label, idx)
        if label in per_digit and len(per_digit[label]) < 100:
            per_digit[label].append(idx)
        if len(first) == 10 and all(len(v) == 100 for v in per_digit.values()):
            break
    if set(first) != set(range(10)) or not all(len(v) == 100 for v in per_digit.values()):
        raise ValueError("Test set did not contain 10 samples for every digit")
    idx10 = [first[d] for d in range(10)]
    idx100 = [idx for d in range(10) for idx in per_digit[d][:10]]
    if args.count in ("10", "both"): export_set("mnist10", images, labels, idx10)
    if args.count in ("100", "both"): export_set("mnist100", images, labels, idx100)
    if args.count == "1000": export_set("mnist1000", images, labels, [idx for d in range(10) for idx in per_digit[d]])
    if args.count == "10000": export_set("mnist10000", images, labels, range(len(images)))
    print("Each .mem contains 784 two-digit hex bytes, row-major grayscale uint8.")
    print("Original ROM, RTL, weights, Vivado project, and bitstream are not modified.")

if __name__ == "__main__":
    main()
