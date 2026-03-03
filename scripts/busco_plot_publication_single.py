#!/usr/bin/env python3

import json
import sys
from pathlib import Path
import matplotlib.pyplot as plt
import matplotlib.patches as patches

# ----------------------------------
# BUSCO COLOR SCHEME
# ----------------------------------
COLOR_S = "#56B4E9"      # Light blue (single-copy)
COLOR_D = "#0072B2"      # Dark blue (duplicated)
COLOR_F = "#F0E442"      # Yellow (fragmented)
COLOR_M = "#D55E00"      # Red (missing)

LEGEND_LABELS = [
    ("Complete (C) and single-copy (S)", COLOR_S),
    ("Complete (C) and duplicated (D)", COLOR_D),
    ("Fragmented (F)", COLOR_F),
    ("Missing (M)", COLOR_M),
]


def load_busco_json(json_path):
    """Parse BUSCO v6 short_summary JSON."""
    with open(json_path) as f:
        data = json.load(f)

    res = data["results"]

    return {
        "label": "SPEC1",                     # <- As requested
        "C": res["Complete BUSCOs"],
        "S": res["Single copy BUSCOs"],
        "D": res["Multi copy BUSCOs"],
        "F": res["Fragmented BUSCOs"],
        "M": res["Missing BUSCOs"],
        "n": res["n_markers"],
    }


def plot_single_busco(json_file, out_prefix):
    """Create a publication-quality single-sample BUSCO plot."""
    X = load_busco_json(json_file)

    label = X["label"]
    S, D, F, M, n = X["S"], X["D"], X["F"], X["M"], X["n"]
    C = X["C"]

    # Percentages
    S_pct = S / n * 100
    D_pct = D / n * 100
    F_pct = F / n * 100
    M_pct = M / n * 100

    # -------------------------------
    # CREATE FIGURE
    # -------------------------------
    fig, ax = plt.subplots(figsize=(12, 5))

    # Stack bars — remove D block completely if D=0
    current_left = 0

    # S block
    ax.barh(label, S_pct, color=COLOR_S, height=0.5)
    current_left += S_pct

    # D block (only if D > 0)
    if D > 0:
        ax.barh(label, D_pct, left=current_left, color=COLOR_D, height=0.5)
        current_left += D_pct

    # F block
    ax.barh(label, F_pct, left=current_left, color=COLOR_F, height=0.5)
    current_left += F_pct

    # M block — correct BUSCO red
    ax.barh(label, M_pct, left=current_left, color=COLOR_M, height=0.5)

    # Text inside the blue region
    text = f"C:{C} [S:{S}, D:{D}], F:{F}, M:{M}, n:{n}"
    ax.text(S_pct * 0.45, label, text,
            va="center", ha="center", fontsize=13, color="black")

    # Axis formatting
    ax.set_xlim(0, 100)
    ax.set_xlabel("% BUSCOs", fontsize=14)
    ax.set_ylabel("")

    # -------------------------------
    # LEGEND ABOVE PLOT (clean)
    # -------------------------------
    handles = [patches.Patch(color=c, label=l) for l, c in LEGEND_LABELS]
    ax.legend(
        handles=handles,
        loc="upper center",
        bbox_to_anchor=(0.5, 1.16),     # ← pushes legend much higher
        ncol=2,
        fontsize=12,
        frameon=False,
        borderaxespad=0,
#        bbox_transform=fig.transFigure  # ← ensures absolute figure coord
    )

    # Clean layout
    plt.tight_layout()

    # -----------------------------------
    # SAVE OUTPUTS
    # -----------------------------------
    out_prefix = Path(out_prefix)
    fig.savefig(out_prefix.with_suffix(".png"), dpi=300)
    fig.savefig(out_prefix.with_suffix(".svg"))
    fig.savefig(out_prefix.with_suffix(".pdf"))

    print(f"[OK] Saved PNG, SVG, PDF → {out_prefix}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage:")
        print(" python busco_plot_publication_single.py <short_summary.json> <output_prefix>")
        sys.exit(1)

    json_file = sys.argv[1]
    out_prefix = sys.argv[2]

    plot_single_busco(json_file, out_prefix)

