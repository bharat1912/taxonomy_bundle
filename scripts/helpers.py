# ============================================================
# lib/helpers.py
# Utility functions for Snakefile_SRAsearch_general.smk
# ============================================================

import re

def slugify(values):
    """
    Create a safe, filesystem-friendly name from a list or string.
    """
    if isinstance(values, list):
        text = "_".join(map(str, values))
    else:
        text = str(values)
    # remove punctuation and compress underscores
    text = re.sub(r"[^\w\-]+", "_", text)
    return re.sub(r"_+", "_", text.strip("_"))

def build_search_flags(filters):
    if not filters:
        return ""

    flags = []
    for key, value in filters.items():
        if value is None or value == "":
            continue

        flag = f"--{key}"

        if isinstance(value, bool):
            if value:
                flags.append(flag)
            continue

        if isinstance(value, list):
            joined = ",".join(map(str, value))
            flags.append(f"{flag} {joined}")
        else:
            # NEUTRALIZING MANEUVER: Use single quotes for the query value
            # This protects Boolean parentheses from shell interpretation
            if key == "query":
                flags.append(f"{flag} '{value}'")
            else:
                flags.append(f'{flag} "{value}"')

    return " ".join(flags)

