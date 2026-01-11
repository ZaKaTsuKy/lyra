# OS/Linux/ai/IsolationForest.jl
# ============================
# Streaming Isolation Forest for Anomaly Detection
# ============================
# Implements Isolation Forest with a sliding window buffer
# for online anomaly detection with O(1) memory per tree.
#
# Reference: Liu, Ting, Zhou (2008) - Isolation Forest

using Random

# ============================
# CONSTANTS
# ============================

const DEFAULT_N_TREES = 100
const DEFAULT_SAMPLE_SIZE = 256
const MAX_TREE_HEIGHT = 10  # ceil(log2(256))

# ============================
# ISOLATION TREE NODE
# ============================

"""
Node in an Isolation Tree.
Internal nodes have split_feature and split_value.
Leaf nodes have size (number of samples that reached here).
"""
mutable struct IsolationTreeNode
    split_feature::Int          # -1 for leaf
    split_value::Float64
    left::Union{IsolationTreeNode,Nothing}
    right::Union{IsolationTreeNode,Nothing}
    size::Int                   # For external nodes (leaves)
    height::Int
end

# Leaf constructor
IsolationTreeNode(size::Int, height::Int) = IsolationTreeNode(-1, 0.0, nothing, nothing, size, height)

# Internal node constructor
IsolationTreeNode(feature::Int, value::Float64, left, right, height::Int) =
    IsolationTreeNode(feature, value, left, right, 0, height)

is_leaf(node::IsolationTreeNode) = node.split_feature == -1

# ============================
# ISOLATION TREE
# ============================

"""Build an isolation tree from a sample of data"""
function build_tree(X::Matrix{Float64}, indices::Vector{Int}, height::Int, max_height::Int, rng::AbstractRNG)
    n_samples = length(indices)
    n_features = size(X, 2)

    # Termination: max height reached or only one sample
    if height >= max_height || n_samples <= 1
        return IsolationTreeNode(n_samples, height)
    end

    # Randomly select a feature
    feature = rand(rng, 1:n_features)

    # Get min/max for this feature across current samples
    feature_values = [X[i, feature] for i in indices]
    min_val, max_val = extrema(feature_values)

    # If all values are the same, create a leaf
    if max_val - min_val < 1e-10
        return IsolationTreeNode(n_samples, height)
    end

    # Random split value between min and max
    split_value = min_val + rand(rng) * (max_val - min_val)

    # Partition indices
    left_indices = Int[]
    right_indices = Int[]

    for i in indices
        if X[i, feature] < split_value
            push!(left_indices, i)
        else
            push!(right_indices, i)
        end
    end

    # Edge case: if partition is degenerate, make a leaf
    if isempty(left_indices) || isempty(right_indices)
        return IsolationTreeNode(n_samples, height)
    end

    # Recursively build children
    left_child = build_tree(X, left_indices, height + 1, max_height, rng)
    right_child = build_tree(X, right_indices, height + 1, max_height, rng)

    return IsolationTreeNode(feature, split_value, left_child, right_child, height)
end

"""Compute path length for a sample in a tree"""
function path_length(node::IsolationTreeNode, x::Vector{Float64}, current_height::Int)::Float64
    if is_leaf(node)
        # Add average path length for unbuilt subtree (c(n) correction)
        return Float64(current_height) + c_factor(node.size)
    end

    if x[node.split_feature] < node.split_value
        return path_length(node.left, x, current_height + 1)
    else
        return path_length(node.right, x, current_height + 1)
    end
end

"""Average path length of unsuccessful search in BST (Equation 1 in paper)"""
function c_factor(n::Int)::Float64
    n <= 1 && return 0.0
    n == 2 && return 1.0
    H = log(n - 1) + 0.5772156649  # Euler-Mascheroni constant
    return 2.0 * H - (2.0 * (n - 1) / n)
end

# ============================
# ISOLATION FOREST
# ============================

"""
Streaming Isolation Forest with sliding window buffer.
"""
mutable struct IsolationForest
    trees::Vector{IsolationTreeNode}
    n_trees::Int
    sample_size::Int
    n_features::Int

    # Sliding window buffer for streaming data
    buffer::Matrix{Float64}
    buffer_idx::Int
    buffer_count::Int

    # State
    trained::Bool
    rng::AbstractRNG

    # Rebuild trigger
    samples_since_rebuild::Int
    rebuild_threshold::Int
end

function IsolationForest(;
    n_trees::Int=DEFAULT_N_TREES,
    sample_size::Int=DEFAULT_SAMPLE_SIZE,
    n_features::Int=6,
    seed::Int=42
)
    buffer = zeros(Float64, sample_size, n_features)

    IsolationForest(
        IsolationTreeNode[],
        n_trees,
        sample_size,
        n_features,
        buffer,
        1,
        0,
        false,
        MersenneTwister(seed),
        0,
        sample_size  # Rebuild after buffer fills
    )
end

"""Add a new sample to the forest's sliding window"""
function add_sample!(forest::IsolationForest, features::Vector{Float64})
    @assert length(features) == forest.n_features "Feature dimension mismatch"

    # Add to circular buffer
    forest.buffer[forest.buffer_idx, :] .= features
    forest.buffer_idx = mod1(forest.buffer_idx + 1, forest.sample_size)
    forest.buffer_count = min(forest.buffer_count + 1, forest.sample_size)
    forest.samples_since_rebuild += 1

    # Check if we should rebuild the forest
    if forest.samples_since_rebuild >= forest.rebuild_threshold && forest.buffer_count >= forest.sample_size ÷ 2
        rebuild!(forest)
    end

    return nothing
end

"""Rebuild the forest from current buffer"""
function rebuild!(forest::IsolationForest)
    n_samples = forest.buffer_count
    n_samples < 10 && return  # Not enough samples yet

    # Subsample if needed
    actual_sample_size = min(n_samples, forest.sample_size)
    max_height = ceil(Int, log2(actual_sample_size))

    # Build new trees
    forest.trees = Vector{IsolationTreeNode}(undef, forest.n_trees)

    for t in 1:forest.n_trees
        # Random subsample indices
        indices = randperm(forest.rng, n_samples)[1:actual_sample_size]

        # Build tree
        forest.trees[t] = build_tree(forest.buffer, indices, 0, max_height, forest.rng)
    end

    forest.trained = true
    forest.samples_since_rebuild = 0
    return nothing
end

"""
Compute anomaly score for a sample.
Returns a value between 0 (normal) and 1 (anomalous).
"""
function anomaly_score(forest::IsolationForest, features::Vector{Float64})::Float64
    !forest.trained && return 0.0  # Not enough data yet
    @assert length(features) == forest.n_features

    # Compute average path length across all trees
    avg_path = 0.0
    for tree in forest.trees
        avg_path += path_length(tree, features, 0)
    end
    avg_path /= forest.n_trees

    # Normalize to [0, 1] using equation 2 from paper
    # s(x, n) = 2^(-E(h(x)) / c(n))
    c = c_factor(forest.sample_size)
    c < 1e-10 && return 0.0

    score = 2.0^(-avg_path / c)
    return clamp(score, 0.0, 1.0)
end

"""Check if a sample is anomalous (score > threshold)"""
function is_anomaly(forest::IsolationForest, features::Vector{Float64}; threshold::Float64=0.6)::Bool
    return anomaly_score(forest, features) > threshold
end

# ============================
# FEATURE VECTOR BUILDER
# ============================

"""
Build the standard feature vector for anomaly detection.
Order: [cpu_load, mem_pct, disk_io, net_traffic, fan_rpm, vcore_voltage]
"""
function build_feature_vector(
    cpu_load::Float64,
    mem_pct::Float64,
    disk_io::Float64,
    net_traffic::Float64,
    fan_rpm::Int,
    vcore_voltage::Float64
)::Vector{Float64}
    # Normalize to similar scales
    return Float64[
        clamp(cpu_load / 100.0, 0.0, 1.0),           # CPU load [0-1]
        clamp(mem_pct / 100.0, 0.0, 1.0),            # Memory [0-1]
        clamp(disk_io / 1e9, 0.0, 1.0),              # Disk I/O normalized to ~1GB/s
        clamp(net_traffic / 1e9, 0.0, 1.0),          # Network normalized to ~1Gbps
        clamp(Float64(fan_rpm) / 5000.0, 0.0, 1.0),  # Fan RPM normalized to 5000 RPM
        clamp(vcore_voltage / 2.0, 0.0, 1.0)         # Voltage normalized to 2V
    ]
end

"""Build feature vector from SystemMonitor"""
function build_feature_vector_from_monitor(monitor)::Vector{Float64}
    # CPU load (normalized by core count)
    cpu_load = monitor.cpu_info.load1 / max(1, Sys.CPU_THREADS) * 100.0

    # Memory percentage
    mem_pct = if monitor.memory.total_kb > 0
        (monitor.memory.used_kb / monitor.memory.total_kb) * 100.0
    else
        0.0
    end

    # Total disk I/O (bytes/sec)
    disk_io = 0.0
    for disk in monitor.disks
        disk_io += disk.read_bps + disk.write_bps
    end

    # Network traffic (bytes/sec)
    net_traffic = monitor.network.rx_bps + monitor.network.tx_bps

    # Hardware sensors
    fan_rpm = 0
    vcore = 0.0
    if monitor.hardware !== nothing
        fan_rpm = monitor.hardware.primary_cpu_fan_rpm
        vcore = monitor.hardware.vcore_voltage
    end

    return build_feature_vector(cpu_load, mem_pct, disk_io, net_traffic, fan_rpm, vcore)
end
