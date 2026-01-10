# debug_disk.jl
# Script de diagnostic pour comprendre pourquoi les disques ne sont pas détectés

println("="^60)
println("DIAGNOSTIC DISQUES - OMNI MONITOR")
println("="^60)

# ============================================
# PARTIE 1: DISK SPACE (df)
# ============================================

println("\n[1] Test de la commande 'df'")
println("-"^40)

try
    output = read(`df -BG --output=target,size,used,avail,pcent`, String)
    println("Sortie brute de 'df -BG':")
    println(output)
catch e
    println("ERREUR: Impossible d'exécuter 'df': $e")
end

println("\n[2] Analyse des points de montage")
println("-"^40)

function is_relevant_mount(mount::AbstractString)
    m = String(mount)
    m == "/" && return true
    startswith(m, "/home") && return true
    startswith(m, "/mnt/") && return true
    startswith(m, "/data") && return true
    startswith(m, "/opt") && return true
    startswith(m, "/var") && return true
    return false
end

function is_noise_mount(mount::AbstractString)
    m = String(mount)
    occursin("docker", m) && return true
    occursin("wslg", m) && return true
    occursin("overlay", m) && return true
    occursin("shm", m) && return true
    occursin("snap", m) && return true
    occursin("loop", m) && return true
    return false
end

try
    output = read(`df -BG --output=target,size,used,avail,pcent`, String)
    lines = split(output, '\n')

    for (i, line) in enumerate(lines)
        i == 1 && continue  # Skip header
        isempty(strip(line)) && continue

        parts = split(line)
        length(parts) < 5 && continue

        mount = String(parts[1])
        relevant = is_relevant_mount(mount)
        noise = is_noise_mount(mount)

        status = if noise
            "✗ BRUIT (filtré)"
        elseif relevant
            "✓ PERTINENT"
        else
            "✗ NON PERTINENT (filtré)"
        end

        println("  $mount → $status")
    end
catch e
    println("ERREUR: $e")
end

# ============================================
# PARTIE 2: DISK IO (/proc/diskstats)
# ============================================

println("\n[3] Contenu de /proc/diskstats")
println("-"^40)

const DISKSTATS_PATH = "/proc/diskstats"

if isfile(DISKSTATS_PATH)
    println("✓ Fichier existe")
    content = read(DISKSTATS_PATH, String)
    println("\nContenu brut (premières lignes):")
    for (i, line) in enumerate(split(content, '\n'))
        i > 20 && break
        println("  $line")
    end
else
    println("✗ FICHIER NON TROUVÉ: $DISKSTATS_PATH")
end

println("\n[4] Analyse des devices")
println("-"^40)

function is_valid_disk_device(dev::AbstractString)
    d = String(dev)
    startswith(d, "sd") && return true
    startswith(d, "nvme") && return true
    startswith(d, "vd") && return true
    startswith(d, "xvd") && return true
    startswith(d, "hd") && return true
    startswith(d, "mmcblk") && return true
    return false
end

try
    for line in eachline(DISKSTATS_PATH)
        parts = split(line)
        length(parts) < 14 && continue

        dev = String(parts[3])
        valid = is_valid_disk_device(dev)

        # Test du regex pour filtrer les partitions
        is_whole_disk = match(r"^(sd[a-z]+|nvme\d+n\d+|vd[a-z]+|xvd[a-z]+|hd[a-z]+|mmcblk\d+)$", dev) !== nothing

        if valid
            status = is_whole_disk ? "✓ DISQUE ENTIER" : "⚠ PARTITION (filtré)"
            reads = parts[6]
            writes = parts[10]
            println("  $dev → $status (reads: $reads, writes: $writes)")
        end
    end
catch e
    println("ERREUR: $e")
end

println("\n[5] Test avec lsblk")
println("-"^40)

try
    output = read(`lsblk -d -o NAME,TYPE,SIZE`, String)
    println(output)
catch e
    println("Impossible d'exécuter 'lsblk': $e")
end

# ============================================
# PARTIE 3: Diagnostic du problème SubString
# ============================================

println("\n[6] Test des types SubString")
println("-"^40)

test_line = "   8       0 sda 12345 0 67890 0 11111 0 22222 0 0 33333 44444"
parts = split(test_line)
if length(parts) >= 3
    dev = parts[3]
    println("Device extrait: '$dev'")
    println("Type: $(typeof(dev))")
    println("Est un String? $(dev isa String)")
    println("Est un AbstractString? $(dev isa AbstractString)")

    # Test startswith
    println("\nTest startswith:")
    println("  startswith(dev, \"sd\") = $(startswith(dev, "sd"))")
    println("  startswith(String(dev), \"sd\") = $(startswith(String(dev), "sd"))")
end

println("\n" * "="^60)
println("FIN DU DIAGNOSTIC")
println("="^60)