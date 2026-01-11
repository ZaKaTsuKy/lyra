import React, { useRef, useMemo, useEffect } from 'react';
import { useFrame } from '@react-three/fiber';
import { Group, Mesh, Color, MeshStandardMaterial, MeshBasicMaterial, BoxGeometry, CylinderGeometry } from 'three';
import { useTelemetryStore } from '../../../store/telemetryStore';
import type { UpdatePayload } from '../../../types/omni';

// ============================================
// Cached data type for animation
// ============================================
interface AnimationData {
    temp: number;
    rpm: number;
}

export const TowerModel: React.FC = () => {
    const cpuBlockRef = useRef<Mesh>(null);
    const cpuFanRef = useRef<Group>(null);
    const caseFanRef = useRef<Group>(null);

    // Reusable Color instance to avoid GC pressure in useFrame
    const targetColor = useRef(new Color());

    // ============================================
    // ✅ FIX: Use ref for live data, updated via subscription
    // This avoids reading the store in useFrame which was causing issues
    // ============================================
    const animationDataRef = useRef<AnimationData>({ temp: 30, rpm: 800 });

    useEffect(() => {
        // Subscribe to store changes, extract only what we need
        const unsubscribe = useTelemetryStore.subscribe(
            (state) => state.liveData,
            (liveData: UpdatePayload | null) => {
                if (liveData) {
                    animationDataRef.current = {
                        temp: liveData.cpu.temp_package || 30,
                        rpm: liveData.hardware_health?.primary_fan_rpm || 800,
                    };
                }
            }
        );

        return unsubscribe;
    }, []);

    // ============================================
    // MATERIALS (created once, disposed on unmount)
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
    }), []);

    // ============================================
    // GEOMETRIES (created once, disposed on unmount)
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
    }), []);

    // ============================================
    // CLEANUP on unmount
    // ============================================
    useEffect(() => {
        return () => {
            Object.values(materials).forEach(mat => mat.dispose());
            Object.values(geometries).forEach(geo => geo.dispose());
        };
    }, [materials, geometries]);

    // ============================================
    // ANIMATION LOOP - Zero store reads, uses ref
    // ============================================
    useFrame((_, delta) => {
        const { temp, rpm } = animationDataRef.current;

        // 1. CPU Temperature -> Color (Green 30°C -> Red 90°C)
        const normalizedTemp = Math.min(Math.max((temp - 30) / 60, 0), 1);

        if (cpuBlockRef.current) {
            targetColor.current.setHSL(0.33 * (1 - normalizedTemp), 1, 0.5);
            materials.cpuBlock.color.lerp(targetColor.current, 0.1);
        }

        // 2. Fan RPM -> Rotation
        const rotationSpeed = (rpm / 60) * 2 * Math.PI * delta;

        if (cpuFanRef.current) {
            cpuFanRef.current.rotation.y -= rotationSpeed;
        }
        if (caseFanRef.current) {
            caseFanRef.current.rotation.x -= rotationSpeed * 0.8;
        }
    });

    return (
        <group dispose={null}>
            {/* --- CASE --- */}
            <mesh position={[0, 2.5, 0]} geometry={geometries.case} material={materials.caseWireframe} />

            {/* --- MOTHERBOARD --- */}
            <mesh position={[-1.1, 2.5, 0]} geometry={geometries.motherboard} material={materials.motherboard} />

            {/* --- CPU BLOCK --- */}
            <group position={[-0.9, 3.5, 0.5]}>
                <mesh ref={cpuBlockRef} geometry={geometries.cpuBlock} material={materials.cpuBlock} />
                <group ref={cpuFanRef} position={[0.25, 0, 0]} rotation={[0, 0, Math.PI / 2]}>
                    <mesh geometry={geometries.cpuFanHub} material={materials.fanHub} />
                    <mesh rotation={[Math.PI / 2, 0, 0]} geometry={geometries.fanBlade} material={materials.fanBlade} />
                    <mesh rotation={[Math.PI / 2, Math.PI / 2, 0]} geometry={geometries.fanBlade} material={materials.fanBlade} />
                </group>
            </group>

            {/* --- GPU --- */}
            <group position={[-0.5, 1.5, 0]}>
                <mesh geometry={geometries.gpu} material={materials.gpu} />
                <mesh position={[0.1, 0, 1]} geometry={geometries.gpuLed} material={materials.gpuLed} />
            </group>

            {/* --- CASE FAN (Front) --- */}
            <group ref={caseFanRef} position={[1.2, 2.5, 1.5]} rotation={[0, Math.PI / 2, 0]}>
                <mesh rotation={[Math.PI / 2, 0, 0]} geometry={geometries.caseFanHub} material={materials.caseFanHub} />
                <mesh rotation={[0, 0, 0]} geometry={geometries.caseFanBlade} material={materials.caseFanBlade} />
                <mesh rotation={[0, Math.PI / 2, 0]} geometry={geometries.caseFanBlade} material={materials.caseFanBlade} />
            </group>
        </group>
    );
};