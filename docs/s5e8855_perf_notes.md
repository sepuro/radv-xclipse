# Notas de Rendimiento y Heurísticas de Silicon: Samsung Exynos 1580 (Xclipse 540 / CHIP_ARIEL / MGFX2)

Este documento resume las heurísticas de rendimiento, control de hardware del kernel `sgpu.ko` y máscaras de sincronización extraídas de la auditoría de `ref_decompiled/` y los fuentes del kernel Samsung Exynos.

---

## 1. Llamadas DRM IOCTL para Prioridad y Control de Reloj (DVFS)

En el subsistema gráfico de Samsung para el Exynos 1580 (`sgpu`), se utilizan dos mecanismos principales para mantener frecuencias de reloj estables y prioridad en cargas 3D:

### 1.1 `sgpu_driver_control_ioctl` (Opcode 0x5b / 0x9b)
- **Localización**: `sgpu.ko` `.text` @ `0x98f8`. Tabla de ioctls `amdgpu_ioctls_kms` entrada `0x5b`.
- **Definición IOCTL**:
  ```c
  #define DRM_IOCTL_SGPU_DRIVER_CONTROL _IOWR('d', DRM_COMMAND_BASE + 0x5b, struct sgpu_driver_control)
  struct sgpu_driver_control {
      uint32_t cmd; // debe ser 0
      uint32_t pad;
      uint64_t val; // 1 = activar DVFS performance boost / lock clock
  };
  ```
- **Comportamiento en Hardware**: Accede a la estructura interna de gestión de energía del dispositivo (`dev + 0x13ea8`). Cuando `cmd == 0` y `val == 1`, indica al gobernador del kernel que una aplicación 3D intensiva está activa, fijando la frecuencia de GPU y evitando caídas abruptas de reloj por ahorro energético durante renderizado.

### 1.2 Prioridad de Contexto AMDGPU (`amdgpu_ctx_ioctl`, Opcode 0x02)
- **Localización**: `amdgpu_ctx_ioctl` @ `0x1643` en `radv_amdgpu_cs.c`.
- **Valores de Prioridad**:
  - `AMDGPU_CTX_PRIORITY_NORMAL` = `500` (predeterminado).
  - `AMDGPU_CTX_PRIORITY_HIGH` = `1000` (solicitado para contextos de juegos/emuladores 3D).
  - `AMDGPU_CTX_PRIORITY_VERY_HIGH` = `1500` (tiempo real).
- **Efecto**: Elevar la prioridad del contexto a `AMDGPU_CTX_PRIORITY_HIGH` sitúa los envíos de comandos (CS) de la aplicación por delante de compositores secundarios del sistema en el scheduler de `sgpu.ko`, reduciendo la latencia de frame y el jitter.

---

## 2. Combined Depth Cache Flush y Máscara de Bits en `vkCmdPipelineBarrier`

### 2.1 Silicon Defect `VOYAGERSW-1566`
- **Causa**: En el bloque de hardware DB (Depth Block) de los SoCs Samsung MGFX2 (Xclipse 540 / CHIP_ARIEL), existe una limitación de silicio: la emisión aislada de `FLUSH_AND_INV_DB_META` (evento 44) mientras hay peticiones Z activas causa un bloqueo cíclico (deadlock del hardware DB). El motor de comandos CP queda esperando indefinidamente en el fence EOP (`dma_fence_default_wait`), lo que provoca que el kernel reinicie el bloque GPU con `VK_ERROR_DEVICE_LOST`.
- **Estrategia Propietaria**: El driver de Samsung nunca emite `FLUSH_AND_INV_DB_META` de forma aislada. En su lugar, utiliza un vaciado combinado disparado mediante el evento **`V_028A90_CACHE_FLUSH_AND_INV_TS_EVENT`**.

### 2.2 Máscara de Bits Exacta en Mesa RADV
En [`ac_barrier.h`](file:///data/data/com.termux/files/home/xclipse540-driver-workspace/mesa_radv_src/src/amd/common/ac_barrier.h):
- `AC_BARRIER_INV_L2` = `1u << 3` (`0x0008`)
- `AC_BARRIER_WB_L2` = `1u << 4` (`0x0010`)
- `AC_BARRIER_SYNC_AND_INV_CB` = `1u << 6` (`0x0040`)
- `AC_BARRIER_SYNC_AND_INV_CB_META` = `1u << 7` (`0x0080`)
- `AC_BARRIER_SYNC_AND_INV_DB` = `1u << 8` (`0x0100`)
- `AC_BARRIER_SYNC_AND_INV_DB_META` = `1u << 9` (`0x0200`)

### 2.3 Regla de Optimización para Evitar Invalidación Innecesaria de L2:
1. **Máscara de Vaciado Combinado**:
   ```c
   /* Activar CB junto a DB para disparar CACHE_FLUSH_AND_INV_TS_EVENT */
   cmd_buffer->state.flush_bits |= AC_BARRIER_SYNC_AND_INV_CB;
   /* Inhibir explícitamente el evento peligroso DB_META */
   cmd_buffer->state.flush_bits &= ~AC_BARRIER_SYNC_AND_INV_DB_META;
   ```
2. **Preservación de Caché L2 (`~AC_BARRIER_INV_L2`)**:
   - `CACHE_FLUSH_AND_INV_TS_EVENT` vuelca las cachés de datos CB y DB hacia L2.
   - La invalidación global de L2 (`AC_BARRIER_INV_L2`) **NO** debe emitirse en barreras de profundidad ordinarias (transiciones de `VK_IMAGE_ASPECT_DEPTH_BIT` / `STENCIL_BIT` a lectura de shader).
   - Dejar L2 intacta permite reutilizar texturas y buffers de vértices entre pases de renderizado, evitando miles de ciclos de penalización por recargas de memoria externa LPDDR5X.
3. **Restricción a Aspectos Depth/Stencil**:
   - El workaround se ejecuta exclusivamente cuando la barrera involucra `VK_IMAGE_ASPECT_DEPTH_BIT` o `VK_IMAGE_ASPECT_STENCIL_BIT`. Las pasadas de color puro o compute (`VK_QUEUE_COMPUTE` / dispatches) no modifican ni activan el Combined Depth Flush, ahorrando miles de flushes redundantes por segundo.
