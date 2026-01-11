import React, { useRef, useMemo, useEffect, useState } from 'react';
import { useFrame } from '@react-three/fiber';
import { Html } from '@react-three/drei';
import { Group, Mesh, Color, MeshStandardMaterial, MeshBasicMaterial, BoxGeometry, CylinderGeometry } from 'three';
import { useTelemetryStore } from '../../../store/telemetryStore';
import type { UpdatePayload, FullSensorsDTO } from '../../../types/omni';

// ============================================
// Enhanced Animation Data with multi-fan support
// ============================================
interface AnimationData {
    cpuTemp: number;
    gpuTemp: number;
    fans: Map<string, number>;  // label -> RPM
}

// ============================================
// Fan label to mesh mapping config
// ============================================
const FAN_MESH_MAP: Record<string, string> = {
    'cpu': 'cpu_fan',
    'cpu fan': 'cpu_fan',
    'fan1': 'cpu_fan',
    'fan2': 'case_fan',
    'case': 'case_fan',
    'sys': 'case_fan',
    'rear': 'rear_fan',
    'fan3': 'rear_fan',
    'aio': 'cpu_fan',
    'pump': 'cpu_fan',
};

function mapFanToMesh(label: string): string {
    const lbl = label.toLowerCase();
    for (const [key, mesh] of Object.entries(FAN_MESH_MAP)) {
        if (lbl.includes(key)) return mesh;
    }
    return 'case_fan';  // Default
}

// ============================================
// 3D Tooltip Component
// ============================================
interface TooltipProps {
    visible: boolean;
    position: [number, number, number];
    title: string;
    value: string;
    unit?: string;
}

const Tooltip3D: React.FC<TooltipProps> = ({ visible, position, title, value, unit }) => {
    if (!visible) return null;

    return (
        <Html position={position} center style={{ pointerEvents: 'none' }}>
            <div className="bg-black/80 backdrop-blur-sm px-3 py-2 rounded-lg text-white text-xs whitespace-nowrap">
                <div className="font-bold">{title}</div>
                <div className="text-lg font-mono">
                    {value}
                    {unit && <span className="text-gray-400 ml-1">{unit}</span>}
                </div>
            </div>
        </Html>
    );
};

// ============================================
// TowerModel V2 - Enhanced Digital Twin
// ============================================
export const TowerModel: React.FC = () => {
    const cpuBlockRef = useRef<Mesh>(null);
    const gpuBlockRef = useRef<Mesh>(null);
    const cpuFanRef = useRef<Group>(null);
    const caseFanRef = useRef<Group>(null);
    const rearFanRef = useRef<Group>(null);

    // Hover state for tooltips
    const [hoveredComponent, setHoveredComponent] = useState<string | null>(null);

    // Reusable Color instances
    const targetColorCpu = useRef(new Color());
    const targetColorGpu = useRef(new Color());

    // Animation data from store subscription
    const animationDataRef = useRef<AnimationData>({
        cpuTemp: 30,
        gpuTemp: 30,
        fans: new Map([['cpu_fan', 800], ['case_fan', 600], ['rear_fan', 700]])
    });

    useEffect(() => {
        const unsubscribe = useTelemetryStore.subscribe(
            (state) => state.liveData,
            (liveData: UpdatePayload | null) => {
                if (!liveData) return;

                const sensors = liveData.full_sensors as FullSensorsDTO | null;

                // CPU temp
                const cpuTemps = sensors?.cpu_temps;
                const cpuTemp = cpuTemps
                    ? (cpuTemps.tctl > 0 ? cpuTemps.tctl : cpuTemps.package)
                    : (liveData.cpu.temp_package || 30);

                // GPU temp
                const gpuTemp = sensors?.gpu_sensors?.edge_temp
                    || (liveData.gpu?.temp ?? 30);

                // Fans - map from FullSensorsDTO
                const fanMap = new Map<string, number>();
                if (sensors?.fans) {
                    for (const fan of sensors.fans) {
                        const meshId = mapFanToMesh(fan.label);
                        // Accumulate if multiple fans map to same mesh
                        const existing = fanMap.get(meshId) || 0;
                        fanMap.set(meshId, Math.max(existing, fan.rpm));
                    }
                } else if (liveData.hardware_health?.primary_fan_rpm) {
                    fanMap.set('cpu_fan', liveData.hardware_health.primary_fan_rpm);
                    fanMap.set('case_fan', liveData.hardware_health.primary_fan_rpm * 0.8);
                }

                animationDataRef.current = {
                    cpuTemp,
                    gpuTemp,
                    fans: fanMap
                };
            }
        );

        return unsubscribe;
    }, []);

    // ============================================
    // MATERIALS
    // ============================================
    const materials = useMemo(() => ({
        caseWireframe: new MeshBasicMaterial({ color: '#4ade80', wireframe: true, opacity: 0.3, transparent: true }),
        motherboard: new MeshStandardMaterial({ color: '#334155', roughness: 0.8 }),
        cpuBlock: new MeshStandardMaterial({ color: '#22c55e' }),
        fanHub: new MeshStandardMaterial({ color: '#94a3b8' }),
        fanBlade: new MeshStandardMaterial({ color: '#cbd5e1' }),
        gpu: new MeshStandardMaterial({ color: '#475569', metalness: 0.6 }),
        gpuLed: new MeshStandardMaterial({ color: '#0ea5e9', emissive: '#0ea5e9', emissiveIntensity: 0.5 }),
        caseFanHub: new MeshStandardMaterial({ color: '#1e293b' }),
        caseFanBlade: new MeshStandardMaterial({ color: '#64748b' }),
        rearFanHub: new MeshStandardMaterial({ color: '#1e293b' }),
        rearFanBlade: new MeshStandardMaterial({ color: '#64748b' }),
    }), []);

    // ============================================
    // GEOMETRIES
    // ============================================
    const geometries = useMemo(() => ({
        case: new BoxGeometry(2.5, 5, 5),
        motherboard: new BoxGeometry(0.2, 4.5, 4.5),
        cpuBlock: new BoxGeometry(0.4, 0.8, 0.8),
        cpuFanHub: new CylinderGeometry(0.35, 0.35, 0.1, 32),
        fanBlade: new BoxGeometry(0.1, 0.7, 0.05),
        gpu: new BoxGeometry(1.5, 0.3, 3),
        gpuLed: new BoxGeometry(1.6, 0.1, 0.2),
        caseFanHub: new CylinderGeometry(0.5, 0.5, 0.1, 32),
        caseFanBlade: new BoxGeometry(0.1, 0.9, 0.05),
        rearFanHub: new CylinderGeometry(0.4, 0.4, 0.1, 32),
        rearFanBlade: new BoxGeometry(0.08, 0.75, 0.04),
    }), []);

    // Cleanup
    useEffect(() => {
        return () => {
            Object.values(materials).forEach(mat => mat.dispose());
            Object.values(geometries).forEach(geo => geo.dispose());
        };
    }, [materials, geometries]);

    // ============================================
    // ANIMATION LOOP - Enhanced with multi-fan
    // ============================================
    useFrame((_, delta) => {
        const { cpuTemp, gpuTemp, fans } = animationDataRef.current;

        // CPU Temperature -> Color (Green 30°C -> Red 90°C)
        const normalizedCpuTemp = Math.min(Math.max((cpuTemp - 30) / 60, 0), 1);
        if (cpuBlockRef.current) {
            targetColorCpu.current.setHSL(0.33 * (1 - normalizedCpuTemp), 1, 0.5);
            materials.cpuBlock.color.lerp(targetColorCpu.current, 0.1);
        }

        // GPU Temperature -> Color
        const normalizedGpuTemp = Math.min(Math.max((gpuTemp - 30) / 70, 0), 1);
        if (gpuBlockRef.current) {
            targetColorGpu.current.setHSL(0.55 * (1 - normalizedGpuTemp), 0.8, 0.35);
            materials.gpu.color.lerp(targetColorGpu.current, 0.1);
        }

        // CPU Fan rotation
        const cpuRpm = fans.get('cpu_fan') || 800;
        const cpuRotation = (cpuRpm / 60) * 2 * Math.PI * delta;
        if (cpuFanRef.current) {
            cpuFanRef.current.rotation.y -= cpuRotation;
        }

        // Case Fan rotation
        const caseRpm = fans.get('case_fan') || 600;
        const caseRotation = (caseRpm / 60) * 2 * Math.PI * delta;
        if (caseFanRef.current) {
            caseFanRef.current.rotation.x -= caseRotation;
        }

        // Rear Fan rotation
        const rearRpm = fans.get('rear_fan') || 700;
        const rearRotation = (rearRpm / 60) * 2 * Math.PI * delta;
        if (rearFanRef.current) {
            rearFanRef.current.rotation.x += rearRotation;
        }
    });

    // Get current values for tooltips
    const data = animationDataRef.current;

    return (
        <group dispose={null}>
            {/* --- CASE --- */}
            <mesh position={[0, 2.5, 0]} geometry={geometries.case} material={materials.caseWireframe} />

            {/* --- MOTHERBOARD --- */}
            <mesh position={[-1.1, 2.5, 0]} geometry={geometries.motherboard} material={materials.motherboard} />

            {/* --- CPU BLOCK --- */}
            <group position={[-0.9, 3.5, 0.5]}>
                <mesh
                    ref={cpuBlockRef}
                    geometry={geometries.cpuBlock}
                    material={materials.cpuBlock}
                    onPointerEnter={() => setHoveredComponent('cpu')}
                    onPointerLeave={() => setHoveredComponent(null)}
                />
                <Tooltip3D
                    visible={hoveredComponent === 'cpu'}
                    position={[0, 0.7, 0]}
                    title="CPU"
                    value={data.cpuTemp.toFixed(0)}
                    unit="°C"
                />
                <group ref={cpuFanRef} position={[0.25, 0, 0]} rotation={[0, 0, Math.PI / 2]}>
                    <mesh geometry={geometries.cpuFanHub} material={materials.fanHub} />
                    <mesh rotation={[Math.PI / 2, 0, 0]} geometry={geometries.fanBlade} material={materials.fanBlade} />
                    <mesh rotation={[Math.PI / 2, Math.PI / 2, 0]} geometry={geometries.fanBlade} material={materials.fanBlade} />
                </group>
            </group>

            {/* --- GPU --- */}
            <group position={[-0.5, 1.5, 0]}>
                <mesh
                    ref={gpuBlockRef}
                    geometry={geometries.gpu}
                    material={materials.gpu}
                    onPointerEnter={() => setHoveredComponent('gpu')}
                    onPointerLeave={() => setHoveredComponent(null)}
                />
                <Tooltip3D
                    visible={hoveredComponent === 'gpu'}
                    position={[0, 0.5, 0]}
                    title="GPU"
                    value={data.gpuTemp.toFixed(0)}
                    unit="°C"
                />
                <mesh position={[0.1, 0, 1]} geometry={geometries.gpuLed} material={materials.gpuLed} />
            </group>

            {/* --- CASE FAN (Front) --- */}
            <group position={[1.2, 2.5, 1.5]}>
                <group ref={caseFanRef} rotation={[0, Math.PI / 2, 0]}>
                    <mesh
                        rotation={[Math.PI / 2, 0, 0]}
                        geometry={geometries.caseFanHub}
                        material={materials.caseFanHub}
                        onPointerEnter={() => setHoveredComponent('case_fan')}
                        onPointerLeave={() => setHoveredComponent(null)}
                    />
                    <mesh rotation={[0, 0, 0]} geometry={geometries.caseFanBlade} material={materials.caseFanBlade} />
                    <mesh rotation={[0, Math.PI / 2, 0]} geometry={geometries.caseFanBlade} material={materials.caseFanBlade} />
                </group>
                <Tooltip3D
                    visible={hoveredComponent === 'case_fan'}
                    position={[0, 0.8, 0]}
                    title="Front Fan"
                    value={(data.fans.get('case_fan') || 0).toString()}
                    unit="RPM"
                />
            </group>

            {/* --- REAR FAN (New) --- */}
            <group position={[-1.2, 2.5, 0]}>
                <group ref={rearFanRef} rotation={[0, -Math.PI / 2, 0]}>
                    <mesh
                        rotation={[Math.PI / 2, 0, 0]}
                        geometry={geometries.rearFanHub}
                        material={materials.rearFanHub}
                        onPointerEnter={() => setHoveredComponent('rear_fan')}
                        onPointerLeave={() => setHoveredComponent(null)}
                    />
                    <mesh rotation={[0, 0, 0]} geometry={geometries.rearFanBlade} material={materials.rearFanBlade} />
                    <mesh rotation={[0, Math.PI / 2, 0]} geometry={geometries.rearFanBlade} material={materials.rearFanBlade} />
                </group>
                <Tooltip3D
                    visible={hoveredComponent === 'rear_fan'}
                    position={[0, 0.7, 0]}
                    title="Rear Fan"
                    value={(data.fans.get('rear_fan') || 0).toString()}
                    unit="RPM"
                />
            </group>
        </group>
    );
};