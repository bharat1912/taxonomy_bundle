import csv, os, re
from collections import defaultdict, Counter

BACLIFE = os.path.expanduser("~/software/taxonomy_bundle/bacLIFE")
GFF_DIR = os.path.join(BACLIFE, "intermediate_files/annot")
MEGA    = os.path.join(BACLIFE, "MEGAMATRIX.txt")
OUTPUT  = os.path.expanduser(
    "~/Desktop/Halophiles_Baclife_Project/v5/operon_analysis/")
os.makedirs(OUTPUT, exist_ok=True)

TARGET_CLUSTERS = {
    "cluster_000676": "Rnf-RnfC/RnfD",
    "cluster_000789": "Rnf-RnfA/RnfB",
    "cluster_005623": "Rnf-RnfG",
    "cluster_001102": "KorA-OFOR_alpha",
    "cluster_000512": "KorB-OFOR_beta",
    "cluster_003808": "FxsA-phage_exclusion",
    "cluster_000692": "ABC_Fe3+_transporter",
    "cluster_000605": "Radical_SAM",
}

# Step 1: Load MEGAMATRIX cluster -> (genome, position) pairs
print("Loading MEGAMATRIX...")
cluster_loci = defaultdict(list)
with open(MEGA) as f:
    reader = csv.DictReader(f, delimiter=' ', quotechar='"')
    for row in reader:
        cid  = (row.get('clusters') or '').strip('"')
        desc = (row.get('descriptions') or '').strip('"')
        if cid not in TARGET_CLUSTERS or not desc:
            continue
        for entry in desc.split(','):
            entry = entry.strip()
            if '|' in entry:
                genome, pos = entry.rsplit('|', 1)
                cluster_loci[cid].append((genome.strip(), int(pos.strip())))

for cid, loci in cluster_loci.items():
    print(f"  {cid} ({TARGET_CLUSTERS[cid]}): {len(loci)} instances")

# Step 2: For each genome, build position -> locus_tag map from .faa
# and locus_tag -> gene record from .gff
print("\nBuilding genome maps...")

def find_genome_dir(genome_name):
    """Find annot subdirectory for genome"""
    # genome_name like Halothermothrix_orenii_DSM18212
    # dir like orenii_DSM18212_O
    parts = genome_name.split('_')
    for dirpath, dirs, files in os.walk(GFF_DIR):
        dirname = os.path.basename(dirpath)
        # Match last 2 parts of genome name in dirname
        if len(parts) >= 2 and all(p in dirname for p in parts[-2:]):
            return dirpath
        # Or full genome name
        if genome_name.replace('_O','') in dirpath:
            return dirpath
    return None

genome_cache = {}  # genome -> (pos_to_locus, locus_to_gene, genes_sorted)

def load_genome(genome_name):
    if genome_name in genome_cache:
        return genome_cache[genome_name]
    
    gdir = find_genome_dir(genome_name)
    if not gdir:
        return None, None, None
    
    # Find faa and gff files
    faa_file = gff_file = None
    for fn in os.listdir(gdir):
        if fn.endswith('.faa') and 'ext_prot' not in fn:
            faa_file = os.path.join(gdir, fn)
        if fn.endswith('.gff'):
            gff_file = os.path.join(gdir, fn)
    
    if not faa_file or not gff_file:
        return None, None, None
    
    # Build position -> locus_tag from faa
    pos_to_locus = {}
    pos = 0
    with open(faa_file) as f:
        for line in f:
            if line.startswith('>'):
                pos += 1
                # header like >DSM18212_00005 product name
                tag = line[1:].split()[0]
                pos_to_locus[pos] = tag
    
    # Build locus_tag -> gene record from gff
    locus_to_gene = {}
    genes_sorted  = []
    with open(gff_file) as f:
        for line in f:
            if line.startswith('#') or '\t' not in line:
                continue
            parts = line.strip().split('\t')
            if len(parts) < 9 or parts[2] != 'CDS':
                continue
            contig = parts[0]
            start  = int(parts[3])
            end    = int(parts[4])
            strand = parts[6]
            attrs  = dict(re.findall(r'(\w+)=([^;]+)', parts[8]))
            locus   = attrs.get('locus_tag','')
            product = attrs.get('product','hypothetical protein')
            gene    = attrs.get('gene','')
            if locus:
                rec = (contig, start, end, strand, locus, product, gene)
                locus_to_gene[locus] = rec
                genes_sorted.append(rec)
    
    genes_sorted.sort(key=lambda x: (x[0], x[1]))
    genome_cache[genome_name] = (pos_to_locus, locus_to_gene, genes_sorted)
    return pos_to_locus, locus_to_gene, genes_sorted

# Step 3: Find neighbourhoods
print("\nAnalysing neighbourhoods...")
WINDOW  = 6
results = []
matched = defaultdict(int)

for cid, label in TARGET_CLUSTERS.items():
    loci = cluster_loci.get(cid, [])
    genome_loci = defaultdict(list)
    for genome, pos in loci:
        genome_loci[genome].append(pos)
    
    for genome, positions in genome_loci.items():
        pos_to_locus, locus_to_gene, genes_sorted = load_genome(genome)
        if pos_to_locus is None:
            continue
        
        for pos in positions[:1]:  # first instance per genome
            locus = pos_to_locus.get(pos)
            if not locus:
                continue
            target_gene = locus_to_gene.get(locus)
            if not target_gene:
                continue
            
            matched[cid] += 1
            idx = genes_sorted.index(target_gene)
            start_idx = max(0, idx - WINDOW)
            end_idx   = min(len(genes_sorted), idx + WINDOW + 1)
            neighbours = [g for g in genes_sorted[start_idx:end_idx]
                          if g[0] == target_gene[0]]
            
            for n in neighbours:
                offset = genes_sorted.index(n) - idx
                results.append({
                    'cluster':   cid,
                    'LAG_label': label,
                    'genome':    genome,
                    'locus_tag': n[4],
                    'gene_name': n[6],
                    'product':   n[5],
                    'strand':    n[3],
                    'contig':    n[0],
                    'start':     n[1],
                    'end':       n[2],
                    'offset':    offset,
                    'is_target': offset == 0
                })

# Step 4: Write output
out_file = os.path.join(OUTPUT, "LAG_operon_neighbourhoods_v3.tsv")
fieldnames = ['cluster','LAG_label','genome','contig','start','end',
              'strand','locus_tag','gene_name','product','offset','is_target']
with open(out_file, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter='\t')
    writer.writeheader()
    writer.writerows(results)

print(f"\nWritten: {out_file} ({len(results)} rows)")

# Step 5: Summary
print("\n=== Neighbourhood summary ===")
for cid, label in TARGET_CLUSTERS.items():
    n = matched[cid]
    subset = [r for r in results if r['cluster']==cid and not r['is_target']]
    if not subset:
        print(f"\n{label}: 0 matched")
        continue
    named = Counter(r['gene_name'] for r in subset if r['gene_name'])
    prods = Counter(r['product'] for r in subset)
    print(f"\n{label} ({cid}) — {n} genomes matched:")
    if named:
        print(f"  Named neighbours: {dict(named.most_common(8))}")
    print("  Top products:")
    for p,c in prods.most_common(6):
        print(f"    {c:3d}x  {p[:70]}")

# Step 6: Check Rnf operon completeness
print("\n=== Rnf complex operon analysis ===")
rnf_clusters = {
    "cluster_000676": "RnfC/RnfD",
    "cluster_000789": "RnfA/RnfB",
    "cluster_005623": "RnfG",
}
# Check if Rnf subunits are co-localised
rnf_genomes = defaultdict(dict)
for cid, label in rnf_clusters.items():
    for r in results:
        if r['cluster'] == cid and r['is_target']:
            rnf_genomes[r['genome']][cid] = (r['contig'], r['start'])

print(f"Genomes with >=2 Rnf subunits detected:")
for genome, subunits in rnf_genomes.items():
    if len(subunits) >= 2:
        contigs = set(v[0] for v in subunits.values())
        co_located = len(contigs) == 1
        print(f"  {genome}: {list(subunits.keys())} "
              f"{'CO-LOCALISED' if co_located else 'DIFFERENT CONTIGS'}")
