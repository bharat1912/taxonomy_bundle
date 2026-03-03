import os
import sys

# Usage: python map_isolates.py <input_dir> <output_file>
input_dir = sys.argv[1]
output_file = sys.argv[2]

with open(output_file, "w") as out:
    out.write("ID\tLABEL\n") # Header for iTOL
    for filename in os.listdir(input_dir):
        if filename.endswith(".faa"):
            isolate = filename.replace(".faa", "")
            with open(os.path.join(input_dir, filename), "r") as f:
                for line in f:
                    if line.startswith(">"):
                        tag = line.split()[0].replace(">", "")
                        out.write(f"{tag}\t{isolate}\n")
