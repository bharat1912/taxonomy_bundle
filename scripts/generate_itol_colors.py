import sys
import re

# Colors (Hex codes)
RED = "#e6194B"    # New Genus (Anoxybacteroides/Cal/Amp/NL1.2)
BLUE = "#4363d8"   # Old Genus (Anoxybacillus flavithermus group)
GRAY = "#a9a9a9"   # Outgroups (Geobacillus/Parageobacillus)

tree_path = "/media/bharat/volume2/Anoxybacillaceaea/clean_proteins/OrthoFinder/Results_Gupta_Audit/Species_Tree/SpeciesTree_rooted.txt"
output_file = "itol_color_strip.txt"

# Identify names in Newick format (everything between '(' or ',' and ':')
with open(tree_path, "r") as f:
    tree_content = f.read()
    names = re.findall(r'[ ( ,]([^():, ]+):', tree_content)

with open(output_file, "w") as out:
    # Use individual write statements to ensure proper line breaks
    out.write("DATASET_COLORSTRIP\n")
    out.write("SEPARATOR COMMA\n")
    out.write("DATASET_LABEL,Taxonomic_Audit\n")
    out.write("COLOR,#ff0000\n")
    out.write("DATA\n")

    for name in set(names):
        # Logic based on Gupta 2024 Audit
        if any(x in name for x in ["Cal_", "Amp_", "NL1.2", "rupiensis"]):
            color = RED
        elif "Anoxybacillus" in name:
            color = BLUE
        else:
            color = GRAY
        
        out.write(f"{name},{color}\n")

print(f"Created {output_file}. Drag and drop this onto your iTOL tree!")
