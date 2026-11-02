# Auditoría Técnica y Especificaciones de Portado: Samsung Xclipse 540 (Exynos 1580 / s5e8855 / ARIEL)

Este documento técnico consolida los hallazgos de la auditoría de ingeniería inversa realizada sobre el driver propietario de Samsung (`vulkan.s5e8855.so` / `sgpu.ko`) y la base de código de Mesa RADV (`mesa_radv_src/src/amd/`). Sirve como fuente de verdad y especificación canónica para la implementación y portado en userspace de Mesa RADV para el identificador de hardware **`CHIP_ARIEL`** (GPU Samsung Xclipse 540, arquitectura AMD RDNA 3, 2 WGPs / 4 CUs).

---

## 1. Interfaz IOCTL y ABI del Módulo del Kernel `sgpu.ko`

### 1.1 Despacho de IOCTLs en Dos Niveles (Two-Level Dispatch)
El kernel Linux modificado por Samsung (`kernel.elf @ 0xffffffc0809bdecc`) altera la función central `drm_ioctl` para implementar un despacho bifurcado basado en el valor numérico del comando (`nr`):

```c
index = nr - DRM_COMMAND_BASE;            // nr - 0x40
if (index <= 0x5f) {                      // opcodes 0x00 .. 0x5f (nr 0x40 .. 0x9f)
    ioctl = &dev->driver->ioctls[index];  // Tabla amdgpu_ioctls_kms (96 entradas en sgpu.ko @ rodata 0x718)
} else if (nr <= 0xcf) {                  // opcodes 0x60 .. 0x8f (nr 0xa0 .. 0xcf)
    ioctl = &drm_ioctls[nr];              // Tabla DRM Core central indexada DIRECTAMENTE por nr
} else {
    return -EINVAL;
}
```

#### Codificación de Macros
- **Nivel 1 (`sgpu` driver table)**:
  ```c
  #define _IOWR_AMD(op, sz)  _IOWR('d', 0x40 + (op), char[sz])
  // Valor numérico de 32 bits: 0xC0000000 | ('d' << 8) | (0x40 + (op)) | ((sz) << 16)
  ```
- **Nivel 2 (DRM Core table)**:
  ```c
  #define _IOWR_DRM(nr, type) _IOWR('d', nr, type)
  ```

---

### 1.2 Mapeo Completo de Opcodes

#### Nivel 1: Tabla de Driver `sgpu` (`amdgpu_ioctls_kms`, 96 entradas)
Permisos de ejecución: `0x21` = `AUTH | RENDER_ALLOW` (accesible sin autenticación DRM Master desde `/dev/dri/renderD128` y `/dev/dri/card0`), `0x31` = `+MASTER`.

| Opcode | nr | Tamaño Struct | Handler en Kernel | Descripción / Semántica |
|:---:|:---:|:---:|:---|:---|
| **0x00** | 0x40 | 0x20 (32 B) | `amdgpu_gem_create_ioctl` | Creación de Buffer Object GEM |
| **0x01** | 0x41 | 0x08 (8 B) | `amdgpu_gem_mmap_ioctl` | Obtención de mmap offset para CPU mapping |
| **0x02** | 0x42 | 0x10 (16 B) | `amdgpu_ctx_ioctl` | Ciclo de vida y gestión de contextos de GPU |
| **0x03** | 0x43 | 0x18 (24 B) | `amdgpu_bo_list_ioctl` | Creación y reemplazo de listas de Buffer Objects |
| **0x04** | 0x44 | 0x18 (24 B) | `amdgpu_cs_ioctl` | Envío de flujos de comandos PM4 (Command Submission) |
| **0x05** | 0x45 | 0x20 / 0x28 | `amdgpu_info_ioctl` | Consultas de telemetría, DEV_INFO, VRAM y MMR |
| **0x06** | 0x46 | 0x120 (288 B) | `amdgpu_gem_metadata_ioctl` | Consulta y configuración de metadatos de tiling |
| **0x07** | 0x47 | 0x10 (16 B) | `amdgpu_gem_wait_idle_ioctl` | Espera de inactividad de un BO |
| **0x08** | 0x48 | 0x28 (40 B) | `amdgpu_gem_va_ioctl` | Bind y mapeo de direcciones virtuales GPU (VA) |
| **0x09** | 0x49 | 0x20 (32 B) | `amdgpu_cs_wait_ioctl` | Espera por fence de un submission específico |
| **0x10** | 0x50 | 0x10 (16 B) | `amdgpu_gem_op_ioctl` | Operaciones GEM secundarias |
| **0x11** | 0x51 | 0x18 (24 B) | `amdgpu_gem_userptr_ioctl` | Registro de memoria de usuario (userptr) |
| **0x12** | 0x52 | 0x18 (24 B) | `amdgpu_cs_wait_fences_ioctl`| Espera múltiple de sync fences |
| **0x13** | 0x53 | 0x08 (8 B) | `amdgpu_vm_ioctl` | Operaciones sobre espacios de tablas de páginas VM |
| **0x14** | 0x54 | 0x20 (32 B) | `amdgpu_cs_fence_to_handle_ioctl` | Conversión de fence a syncobj handle |
| **0x15** | 0x55 | 0x10 (16 B) | `amdgpu_sched_ioctl` | Control de prioridades del scheduler del kernel |
| **0x16** | **0x56** | **0x138 (312 B)** | **`sgpu_gem_create_ioctl`** | **Handler Custom Samsung: Creación GEM atómica con metadatos** |
| **0x5b** | **0x9b** | **0x18 (24 B)** | **`sgpu_driver_control_ioctl`** | **Handler Custom Samsung: Control de energía y DVFS** |
| **0x5d** | **0x9d** | **0x08 (8 B)** | **`sgpu_instance_data_ioctl`** | **Handler Custom Samsung: Instancias de cliente en kernel** |
| **0x5e** | **0x9e** | **0x44 (68 B)** | **`amdgpu_wgp_gating_ioctl`** | **Handler Custom Samsung: Control de power gating de WGPs** |
| **0x5f** | **0x9f** | **0x10 (16 B)** | **`sgpu_mem_profile_add`** | **Handler Custom Samsung: Perfilado de memoria de cliente** |

> **Nota de Renumeración**: Samsung renumeró ciertos opcodes respecto a mainline amdgpu (0x06 es metadata, 0x07 wait_idle, 0x09 wait_cs, 0x10 gem_op, 0x12 wait_fences). Todos los handlers estándar están presentes.

#### Nivel 2: Tabla DRM Core (`drm_ioctls`, opcodes 0x60 a 0x8f indexados directamente por `nr`)
| Opcode | `nr` exacto | Handler Core DRM | Función en Driver de Userspace |
|:---:|:---:|:---|:---|
| 0x72 | 0xb2 | `drm_mode_create_dumb` | Reserva de buffers dumb para presentación |
| 0x73 | 0xb3 | `drm_mode_mmap_dumb` | Mapeo de buffers dumb |
| 0x74 | 0xb4 | `drm_mode_destroy_dumb` | Destrucción de buffers dumb |
| **0x7f** | **0xbf** | **`drm_syncobj_create`** | Creación de objetos de sincronización (semáforos) |
| **0x80** | **0xc0** | **`drm_syncobj_destroy`** | Destrucción de syncobjs |
| **0x81** | **0xc1** | **`drm_syncobj_handle_to_fd`** | Exportación de syncobj a sync_file FD de Android |
| **0x82** | **0xc2** | **`drm_syncobj_fd_to_handle`** | Importación de sync_file FD a syncobj handle |
| **0x83** | **0xc3** | **`drm_syncobj_wait`** | Espera binaria por syncobj |
| **0x84** | **0xc4** | **`drm_syncobj_reset`** | Reinicio de estado de syncobj |
| **0x85** | **0xc5** | **`drm_syncobj_signal`** | Señalización manual de syncobj desde CPU |
| **0x8a** | **0xc6** | **`drm_syncobj_timeline_wait`** | Espera de semáforos de línea temporal (Timeline Semaphores) |
| **0x8b** | **0xc7** | **`drm_syncobj_query`** | Consulta del valor actual en Timeline Semaphores |
| **0x8c** | **0xc8** | **`drm_syncobj_transfer`** | Transferencia de timeline point entre syncobjs |
| **0x8d** | **0xc9** | **`drm_syncobj_timeline_signal`** | Señalización CPU de Timeline Semaphores |

---

### 1.3 Estructuras C y Divergencias Críticas de Samsung

#### A. Asignación de Contexto: `amdgpu_ctx_ioctl` (Opcode 0x02, nr 0x42)
*Divergencia Crítica*: En upstream amdgpu, el `ctx_id` asignado se retorna en el offset `+0x10` (`out.alloc.ctx_id`). En el kernel `sgpu.ko` de Samsung, el kernel escribe el `ctx_id` directamente como un `uint64_t` en el offset `0x00`:
```c
union drm_amdgpu_ctx {
    struct {
        uint32_t op;         // @0x00 (1 = ALLOC_CTX, 2 = FREE_CTX, 3 = QUERY_STATE)
        uint32_t flags;      // @0x04
        uint32_t reg_access; // @0x08
        uint32_t pad;        // @0x0C
    } in;
    struct {
        uint64_t ctx_id;     // @0x00 (Samsung devuelve el ID en offset 0)
        uint64_t reserved;   // @0x08
    } out;
};
```

#### B. Envío de Comandos: `amdgpu_cs_ioctl` (Opcode 0x04, nr 0x44)
*Divergencia Crítica*: A diferencia de mainline donde las cabeceras de chunks se transmiten contiguas en el buffer de usuario, Samsung implementa **chunks indirectos**. El campo `chunks_ptr` es un puntero a un array de punteros de 64 bits (`uint64_t *`), y cada puntero apunta a una cabecera de chunk de 16 bytes:
```c
struct drm_amdgpu_cs_in {
    uint32_t ctx_id;         // @0x00 (ID del contexto creado con AMDGPU_CTX)
    uint32_t bo_list;        // @0x04 (Handle opcional de lista BO)
    uint32_t num_chunks;     // @0x08 (Validado: num_chunks > 0 y < 2^28)
    uint32_t flags;          // @0x0C
    uint64_t chunks_ptr;     // @0x10 -> Puntero de usuario a: uint64_t chunk_ptrs[num_chunks]
};

// Estructura de cabecera de chunk individual (16 bytes):
struct drm_amdgpu_cs_chunk {
    uint32_t chunk_id;       // @0x00 (Opcodes 1..16)
    uint32_t length_dw;      // @0x04 (Longitud de la carga útil en dwords de 32 bits)
    uint64_t chunk_data;     // @0x08 -> Puntero de usuario a la estructura de datos del chunk
};
```

**Mapeo de la Tabla de Saltos de Chunks (`.rodata+0x16c0` en `sgpu.ko`):**
1. **`chunk_id = 1` (`amdgpu_cs_p1_ib`)**: Indirect Buffer PM4 (longitud mínima 0x20 dwords):
   ```c
   struct amdgpu_cs_chunk_ib {
       uint32_t pad;
       uint32_t flags;
       uint64_t va_start;     // Dirección virtual GPU del buffer PM4
       uint32_t ib_bytes;     // Tamaño en dwords del comando PM4
       uint32_t ip_type;      // 0 = GFX, 1 = COMPUTE, 2 = SDMA
       uint32_t ip_instance;
       uint32_t ring;
   };
   ```
   *Validación Pass-2 en `amdgpu_cs_patch_jobs` (@ 0x16cd4)*:
   ```c
   if (va_start + ib_bytes * 4 > bo_size + 0x1000)
       return -EINVAL; // Protege contra lecturas fuera de límites de IBs
   ```
2. **`chunk_id = 2` (`amdgpu_cs_p1_user_fence`)**: Fence de usuario (longitud mínima 0x8 dwords):
   ```c
   struct amdgpu_cs_chunk_fence {
       uint32_t handle;       // Handle del BO donde reside el fence
       uint32_t offset;       // Offset en dwords dentro del BO
   };
   ```
3. **`chunk_id = 6` (`amdgpu_cs_p1_bo_handles`)**: Lista de BOs referenciados (longitud mínima 0x18 dwords):
   ```c
   struct amdgpu_cs_chunk_bo_handles {
       uint32_t reserved1;
       uint32_t reserved2;
       uint32_t count;        // Número de Buffer Objects en la lista
       uint32_t info_size;    // Tamaño de cada registro (8 bytes)
       uint64_t handles_ptr;  // Puntero a array: struct { uint32_t handle; uint32_t flags; }[]
   };
   ```
4. **`chunk_id = 10`**: Almacena 64 bits en `parser[+0x1a8]`.
5. **`chunk_id = 3, 4, 5, 7, 8, 9, 16`**: Omitidos sin error (bucle `continue`).
6. **`chunk_id = 11..15`**: Rechazados con error `-EFAULT`.

---

### 1.4 Handlers Propietarios de Samsung

1. **`0x16` — `sgpu_gem_create_ioctl` (312 bytes) @ .text 0x12830**:
   - Asigna un BO GEM e inyecta metadatos y modo de tiling en una llamada atómica.
   - Parámetros: `bo_size` (u64 @ 0x00), `alignment` (u64 @ 0x08), `mode` (u32 @ 0x10, validado `<= 0x3f`, bit 1 obligatorio), `flags` (u64 @ 0x18, validado `~0xcd0 == 0`), `domains` (u64 @ 0x20), `metadata_count` (u32 @ 0x30, validado `<= 256`), `metadata[256]` (@ 0x34..0x134).
2. **`0x5b` — `sgpu_driver_control_ioctl` (24 bytes) @ .text 0x98f8**:
   - Control de energía y gobernador DVFS.
   - Parámetros: `command` (u32 @ 0x00, debe ser 0 estrictamente), `value` (u64 @ 0x08, 0 = reposo, 1 = activo).
3. **`0x5d` — `sgpu_instance_data_ioctl` (8 bytes) @ .text 0x99d4**:
   - Ciclo de vida de instancias locales del cliente en el kernel.
   - Parámetros: `op` (u32 @ 0x00, 1 = crear, 2 = liberar), `id` (u32 @ 0x04).
   - `op=1` reserva bloque `kmalloc(0xdc0)` asociado a `file_priv`. `op=2` decrementa refcount atómico (CAS) y libera en cero.
4. **`0x5e` — `amdgpu_wgp_gating_ioctl` (68 bytes) @ .text 0x9b70**:
   - Dynamic power gating para WGPs.
   - Parámetros: `op` (u32 @ 0x00, 1 = set mask, 2 = reset, 3 = get telemetry), `value` (u64 @ 0x08), `telemetry` (56 bytes de salida en op=3).
5. **`0x5f` — `sgpu_mem_profile_add` (16 bytes) @ .text 0x9cd8**:
   - Registro de perfiles de memoria userspace.
   - Parámetros: `user_ptr` (u64 @ 0x00), `size` (u32 @ 0x08, validado `<= 0x1000`, 4 KiB máx).

---

## 2. Inicialización de Registros (`mm*`) y Límites de Memoria para Exynos 1580

### 2.1 Identificación y Configuración del Silicio (`CHIP_ARIEL`)
- **SoC**: Samsung Exynos 1580 (`s5e8855`).
- **GPU**: Samsung Xclipse 540.
- **Identificador de chip**: **`CHIP_ARIEL`** (Mesa `AC_XCLIPSE_540`).
- **Codename**: `ARIEL`.
- **IP Level**: `MGFX2_MID` (Samsung MGFX Generación 2 clase media).
- **PCI ID asignado**: `0x73A0` (compartido en el firmware con `CHIP_VANGOGH_LITE`).
- **Kernel Family ID**: **`147`** (`FAMILY_MGFX` / `0x93`).
- **Revisión de Chip (`mmGRBM_CHIP_REVISION`)**:
  - Offset dword: `0x2000` (leído vía `AMDGPU_INFO_READ_MMR_REG`).
  - Valor en hardware: **`0x02300100`**.
  - Decodificación: `Generación = 2`, `Modelo = 0x30` (`MGFX2_MID`), `Stepping = 0x0100`.

### 2.2 Topología de Cómputo
- **Shader Engines (SE)**: 1 Shader Engine (`num_shader_engines = 1`).
- **Shader Arrays (SA)**: 1 Shader Array (`num_shader_arrays_per_engine = 1`).
- **Workgroup Processors (WGP)**: **2 WGPs** (equivalentes a 4 CUs).
- **Compute Units (CU)**: **4 CUs** (`cu_active_number = 4`, `cu_ao_mask = 0x0000000f`, `cu_bitmap[0][0] = 0x0000000f`).
- **Render Backends (RB)**: 1 RB activo (`enabled_rb_pipes_mask = 0x1`).
- **Ray Tracing Hardware**: **No disponible** (`rt = false`). El Xclipse 540 no incluye aceleración por hardware de árboles BVH.

### 2.3 Base MMIO y Registros de Estado en Vivo (Live MMRs)
- **Base de Registros Gráficos**: `AC_XCLIPSE_GC_BASE = 0x1260u` (`GC_BASE__INST0_SEG0`).
- Consultados a través de `AMDGPU_INFO_READ_MMR_REG`:
  - `GRBM_STATUS`: `0x1260 + 0x0da4` = **`0x2004`** (dword) / byte `0x8010`.
  - `GRBM_STATUS2`: `0x1260 + 0x0da2` = **`0x2002`**.
  - `GRBM_STATUS_SE0`: `0x1260 + 0x0da5` = **`0x2005`**.
  - `GRBM_STATUS_SE1`: `0x1260 + 0x0da6` = **`0x2006`**.
  - `CP_STAT`: `0x1260 + 0x0f40` = **`0x21a0`**.
  - `CP_STALLED_STAT1`: `0x1260 + 0x0f3d` = **`0x219d`**.
  - `CP_STALLED_STAT2`: `0x1260 + 0x0f3e` = **`0x219e`**.
  - `CP_STALLED_STAT3`: `0x1260 + 0x0f3c` = **`0x219c`**.
  - `CP_CPF_BUSY_STAT`: `0x1260 + 0x0e28` = **`0x2088`**.
  - `CP_CPF_STALLED_STAT1`: `0x1260 + 0x0e29` = **`0x2089`**.
  - `CP_CPF_STATUS`: `0x1260 + 0x0e27` = **`0x2087`**.
  - `CP_CPC_BUSY_STAT`: `0x1260 + 0x0e25` = **`0x2085`**.
  - `CP_CPC_STALLED_STAT1`: `0x1260 + 0x0e26` = **`0x2086`**.
  - `CP_CPC_STATUS`: `0x1260 + 0x0e24` = **`0x2084`**.

### 2.4 Remapeo de Registros de Contexto TITAN M2 (`gc_10_4_0_offset_m2.h`)
La GPU Xclipse 540 emplea la disposición de registros TITAN / GC 10.4.0 M2. Sus diferencias con GFX10.3 estándar son:
- `DB_RENDER_CONTROL`: dword `0x000` remapeado a **`0x019`**.
- `DB_DEPTH_VIEW`: dword `0x002` remapeado a **`0x016`**.
- `DB_RENDER_OVERRIDE2`: dword `0x004` remapeado a **`0x017`**.
- `DB_HTILE_DATA_BASE`: dword `0x005` remapeado a **`0x00e`**.
- `DB_DEPTH_SIZE_XY`: dword `0x007` remapeado a **`0x00f`**.
- `CB_TARGET_MASK`: dword `0x08e` remapeado a **`0x37a`**.
- `CB_SHADER_MASK`: dword `0x08f` remapeado a **`0x37b`**.
- `CB_COLOR_CONTROL`: dword `0x202` remapeado a **`0x378`**.
- `VGT_SHADER_STAGES_EN`: dword `0x2d5` remapeado a **`0x2a6`**.
- `VGT_GS_OUT_PRIM_TYPE`: **Cambio de espacio de registro** (sale de CONTEXT `0x29b` y pasa al espacio UCONFIG **`0x241`**).
- **Supresión de Máscaras SH CU**: `R_00B21C_SPI_SHADER_PGM_RSRC3_GS` y `R_00B204_SPI_SHADER_PGM_RSRC4_GS` se suprimen porque en el mapa TITAN colisionan con la mitad alta de la dirección de shader (`PGM_HI`).

### 2.5 Parámetros de Inicialización de Contexto (`ctxinit = true`) y DMA
- Preámbulo de inicialización de tijeras y binner en `ac_xclipse_ctxinit.h`:
  - `PA_SC_SCREEN_SCISSOR_BR`: `0x40004000`.
  - `PA_SC_WINDOW_SCISSOR_TL`: `0x80000000`.
  - `PA_SC_WINDOW_SCISSOR_BR`: `0x40004000`.
  - `PA_SC_CLIPRECT_RULE`: `0x0000ffff`.
  - `PA_SC_GENERIC_SCISSOR_TL`: `0x80000000`.
  - `PA_SC_GENERIC_SCISSOR_BR`: `0x40004000`.
  - `PA_SC_BINNER_CNTL_1`: `0x06ff0154` (budget de 1024 líneas de parameter cache, 1792 primitivas por batch).
  - `PA_SC_BINNER_CNTL_2`: `0x03e00000` (bit 22 SBB_ENABLE, 23 ENABLE_PING_PONG_BIN_ORDER).
- **Prefetch Desactivado (`nopf = true`)**: En el motor CP DMA, el prefetch debe permanecer desactivado para impedir cuelgues del Command Processor.

### 2.6 Límites de Memoria y Memguard
- **Arquitectura de Memoria**: UMA (Unified Memory Architecture). La GPU comparte la memoria LPDDR5X física del sistema.
- **Límite Memguard Guardián**:
  - Monitoreado vía SysFS: `/sys/devices/platform/16e00000.sgpu/mem_info_gtt_used`.
  - Límite máximo de protección: **8192 MB** (`8192ull << 20`). Si la memoria usada más la asignación supera este umbral, el driver rechaza la reserva para prevenir el kernel OOM killer de Android.
- **Espacio de Direcciones Virtuales (VA Space)**:
  - Base `virtual_address_offset`: `0x200000` (2 MiB).
  - Techo `virtual_address_max`: `0xfffffffff8000000` (espacio virtual GPU de 48 bits).
  - Alineación de página GART: 4096 bytes (4 KiB).
  - Fragmento de PTE: 64 KiB.
  - Tamaño máximo de buffer individual: 4 GiB (`RADV_MAX_MEMORY_ALLOCATION_SIZE`).

---

## 3. Sincronización y Depth Cache Flush (Combined Depth Cache Flush)

### 3.1 Defecto de Hardware en el Depth Block (`VOYAGERSW-1566`)
En el diseño estándar de RADV / AMD GFX10.3, las barreras de sincronización que vacían la caché de profundidad generan:
1. `PKT3_EVENT_WRITE` con `V_028A90_FLUSH_AND_INV_DB_META` (evento 44).
2. `PKT3_RELEASE_MEM` con `V_028A90_FLUSH_AND_INV_DB_DATA_TS`.

**El Problema**: En el núcleo de hardware DB de los SoCs Samsung Exynos (familia MGFX1, MGFX2, MGFX3), existe un defecto de silicio documentado en los fuentes del kernel (`VOYAGERSW-1566`):
> *"DB has a limitation to handle concurrent z flush & request ... the problem disappears with removal of DB flush cache."*

Cuando un pipeline emite un flush exclusivo de DB mientras hay peticiones Z activas, el hardware del DB entra en un bloqueo cíclico (deadlock interno). El motor de comandos CP queda esperando indefinidamente en el fence EOP (`dma_fence_default_wait`), lo que provoca que el kernel reinicie el bloque GPU y el driver reporte `VK_ERROR_DEVICE_LOST`.

### 3.2 Solución Propietaria: Combined Depth Cache Flush (`ac_xclipse_full_db_flush`)
El driver propietario de Samsung jamás envía un flush exclusivo de DB ni emite `FLUSH_AND_INV_DB_META` de forma aislada.
En Mesa RADV, la secuencia se neutraliza en `radv_cmd_buffer.c`:
```c
/* Xclipse: flush DB only through CACHE_FLUSH_AND_INV_TS, as the vendor does */
if ((cmd_buffer->state.flush_bits & (AC_BARRIER_SYNC_AND_INV_DB | AC_BARRIER_SYNC_AND_INV_CB)) ==
       AC_BARRIER_SYNC_AND_INV_DB &&
    ac_xclipse_full_db_flush(&pdev->info)) {
   cmd_buffer->state.flush_bits |= AC_BARRIER_SYNC_AND_INV_CB;
}
```
Al incorporar automáticamente el flag `AC_BARRIER_SYNC_AND_INV_CB` cuando se solicita `AC_BARRIER_SYNC_AND_INV_DB`:
1. `ac_barrier.c` evalúa la condición `(flags & AC_BARRIER_SYNC_AND_INV_CB && flags & AC_BARRIER_SYNC_AND_INV_DB)` como verdadera.
2. El evento asignado es **`V_028A90_CACHE_FLUSH_AND_INV_TS_EVENT`**.
3. Se omite de raíz la emisión de `ac_cmdbuf_event_write(V_028A90_FLUSH_AND_INV_DB_META)`.
4. El paquete PM4 `RELEASE_MEM` ejecuta un vaciado unificado de la caché de color (CB) y profundidad (DB) conjuntamente con la invalidación de L2, evitando por completo la condición de carrera del hardware.

### 3.3 Sincronización PWS (Point-Wise Synchronization)
En RDNA 3, el pipeline de vaciado e invalidación se divide entre:
- **`PKT3_RELEASE_MEM`**:
  - Disparado con `CACHE_FLUSH_AND_INV_TS_EVENT`.
  - Secuenciamiento hacia adelante (`S_587_SEQ(V_587_SEQ_FORWARD)`).
  - Vaciado de memorias intermedias L1 y L2 (GL2/GL1 writeback e invalidación).
- **`ACQUIRE_MEM`**:
  - Invalida la caché de instrucciones (`GLI_INV`).
  - Etapa PWS (`pws_stage`): Seleccionada entre `V_581B_CP_PFP` o `V_581B_CP_ME`. La sincronización puede diferirse a `V_581B_PRE_DEPTH` únicamente si no existen invalidaciones pendientes en I-Cache.

### 3.4 Prevención de Hard-Lock en Exportación de Syncobj (`ac_drm_syncobj_wait_materialized`)
En el driver de kernel `sgpu.ko`, exportar un syncobj hacia un descriptor de archivo `sync_file` de Android (`DRM_IOCTL_SYNCOBJ_HANDLE_TO_FD`) antes de que su `dma_fence` haya sido materializado internamente por el scheduler produce un **hard-lock del sistema**.
Para evitarlo, `ac_linux_drm.c` implementa una espera de materialización previa:
```c
dev->p->timeline_wait(dev->p, &syncobj, &point, 1, abs_timeout,
                      DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT |
                      DRM_SYNCOBJ_WAIT_FLAGS_WAIT_AVAILABLE, NULL);
```

---

## 4. Propiedades Reportadas en `vkGetPhysicalDeviceProperties2` y Formatos de Imagen

### 4.1 Propiedades de Dispositivo (`vkGetPhysicalDeviceProperties2`)

| Propiedad Vulkan | Valor para CHIP_ARIEL / Xclipse 540 | Explicación Técnica |
|:---|:---|:---|
| `vendorID` | **`0x144d`** (Samsung) | Identifica el hardware como Samsung para compatibilidad óptima con emuladores y wrappers (Wine / DXVK). |
| `deviceID` | **`0x73a0`** | ID de hardware PCI asignado por el firmware a la serie Xclipse. |
| `deviceName` | `"Samsung Xclipse 540"` / `"AMD RADV ARIEL"` | Nombre de la GPU presentado a la aplicación. |
| `deviceType` | `VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU` | GPU integrada en el SoC Exynos 1580. |
| `driverID` | `VK_DRIVER_ID_MESA_RADV` (`17`) | Identificador del driver Mesa RADV. |
| `conformanceVersion` | **`1.4.5.3`** | `major = 1, minor = 4, subminor = 5, patch = 3`. |
| `maxImageDimension2D` | `16384` | Tamaño máximo de textura 2D. |
| `maxImageDimension3D` | `2048` | Tamaño máximo de textura 3D. |
| `maxImageDimensionCube` | `16384` | Tamaño máximo de cubemaps. |
| `maxComputeWorkGroupSize` | `[1024, 1024, 1024]` | Límites de dimensiones del grupo de trabajo. |
| `maxComputeWorkGroupInvocations` | `1024` | Hilos concurrentes por workgroup. |
| `maxComputeSharedMemorySize` | `65536` (64 KiB) | Memoria Local Compartida (LDS) por workgroup. |
| `maxBoundDescriptorSets` | `32` (`MAX_SETS`) | Sets de descriptores vinculados en simultáneo. |
| `maxPerStageDescriptor*` | `1048576` (1M) | Límite por etapa de Samplers, Buffers e Imágenes. |
| `pipelineCacheUUID` | Hash BLAKE3 de 16 bytes | Generado a partir del Build-ID, versión de ACO y propiedades activas (`radv_xclipse_hash_knobs`). |
| `deviceUUID` | Hash de 16 bytes | Calculado en base a topología PCI (`domain`, `bus`, `dev`, `func`). |
| `driverUUID` | `"AMD-MESA-DRV"` | Cadena fija de 16 bytes para RADV. |

---

### 4.2 Formatos de Imagen en `vkGetPhysicalDeviceImageFormatProperties2`

#### A. Decodificación Nativa por Hardware de ASTC LDR
Samsung incorporó decodificadores de hardware dedicados en la unidad de textura para texturas comprimidas ASTC LDR (`IMG_FMT_ASTC_2D_LDR_*`), por lo que no se requiere emulación por Compute Shader:
- **Formatos soportados nativamente**: Los **28 formatos contiguos** (`VK_FORMAT_ASTC_4x4_UNORM_BLOCK` a `VK_FORMAT_ASTC_12x12_SRGB_BLOCK`).
- **Códigos de formato interno en descriptores T# (Word 1 bits [27:20])**:
  - **LDR UNORM**:
    - `4x4`: **133**, `5x4`: **134**, `5x5`: **135**, `6x5`: **136**, `6x6`: **137**, `8x5`: **138**, `8x6`: **139**, `8x8`: **140**, `10x5`: **141**, `10x6`: **142**, `10x8`: **143**, `10x10`: **144**, `12x10`: **145**, `12x12`: **146**.
  - **LDR sRGB**: Códigos **161 al 174** siguiendo la misma secuencia de bloques.
- **ASTC HDR (`ASTC_*_SFLOAT`)**: Sin soporte por hardware (`textureCompressionASTC_HDR = false`).

#### B. Decodificación Nativa por Hardware de ETC2 / EAC
A pesar de que el núcleo base AMD RDNA carece de soporte de silicio para ETC2 (`has_etc_support = false`), el bloque de textura de Samsung implementa decodificadores de hardware directos:
- **Códigos de formato interno en descriptores T# (Word 1 bits [27:20])**:
  - `VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK` / `ETC1_RGB8`: **123**
  - `VK_FORMAT_ETC2_R8G8B8_SRGB_BLOCK`: **124**
  - `VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK`: **125**
  - `VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK`: **126**
  - `VK_FORMAT_EAC_R11_UNORM_BLOCK`: **127**
  - `VK_FORMAT_EAC_R11_SNORM_BLOCK`: **128**
  - `VK_FORMAT_EAC_R11G11_UNORM_BLOCK`: **129**
  - `VK_FORMAT_EAC_R11G11_SNORM_BLOCK`: **130**
  - `VK_FORMAT_ETC2_R8G8B8A1_UNORM_BLOCK`: **131**
  - `VK_FORMAT_ETC2_R8G8B8A1_SRGB_BLOCK`: **132**

#### C. Soporte y Emulación de Formatos BC1–BC7
- **BC1, BC2, BC3**: Soportados nativamente por hardware en el rasterizador de AMD.
- **BC4, BC5, BC6H, BC7**:
  - Emulados en GPU mediante Compute Shaders de decodificación y re-empaquetado (`radv_meta_bc_decode.c`):
    - `BC4_UNORM` -> Re-codificado a `VK_FORMAT_EAC_R11_UNORM_BLOCK` (o `BC3`).
    - `BC5_UNORM` -> Re-codificado a `VK_FORMAT_EAC_R11G11_UNORM_BLOCK`.
    - `BC7_UNORM` -> Decodificado y re-codificado hacia plano portador ASTC 4x4 (`a7_encode`) o carrier BC3 (`bc_bc3_encode`).
    - `BC4/BC5_SNORM` -> Re-codificado a `EAC_R11/R11G11_SNORM` (o planos exactos R8/RG8_SNORM).
    - `BC6H_UFLOAT` -> Re-codificado a `VK_FORMAT_B10G11R11_UFLOAT_PACK32` (o `RGBA16F`).
    - `BC6H_SFLOAT` -> `VK_FORMAT_R16G16B16A16_SFLOAT`.

#### D. Integración con `AHardwareBuffer` (Android)
- Implementación completa de la extensión `VK_ANDROID_external_memory_android_hardware_buffer`.
- Asignación de memoria Gralloc vía buffers dma-buf exportados desde `/dev/dma_heap/system`.
- **Soporte de Formatos Multi-plano Disjoint (Samsung NV12M)**: El driver maneja buffers AHardwareBuffer con planos de video independientes (Y y UV en dma-bufs separados), creando sub-BOs independientes para cada plano (`mem->ahb_plane_bo[]`) y vinculándolos vía `radv_BindImageMemory2`.

---

## 5. Directrices Clave para la Fase 2 (Inyección en Mesa RADV)

1. **Winsys (`vulkan/winsys/amdgpu/` y `common/ac_linux_drm.c`)**:
   - Asegurar que la estructura de envío de CS (`amdgpu_cs_ioctl`) continúe usando el array indirecto de punteros a chunks (`uint64_t *`).
   - Mantener el retorno de `ctx_id` en el offset 0x00 para `amdgpu_ctx_ioctl`.
   - Verificar la comprobación del techo de memoria memguard (`8192ull << 20`) en `radv_amdgpu_bo.c`.
2. **Command Buffer (`vulkan/radv_cmd_buffer.c`)**:
   - Garantizar que para `CHIP_ARIEL` (`AC_XCLIPSE_540`), cualquier flush con `AC_BARRIER_SYNC_AND_INV_DB` active automáticamente `AC_BARRIER_SYNC_AND_INV_CB` para disparar el vaciado combinado `CACHE_FLUSH_AND_INV_TS_EVENT`.
3. **Physical Device (`vulkan/radv_physical_device.c`)**:
   - **Desactivar NGG Culling por defecto para `CHIP_ARIEL`**: Debido a su configuración reducida de 2 WGPs / 4 CUs, el filtrado NGG genera sobrecarga de geometría en lugar de ganancia. Debe mantenerse desactivado a menos que se fuerce explícitamente mediante `RADV_PERFTEST=nggc`.
   - Mantener activas las extensiones requeridas por DXVK y VKD3D (`VK_EXT_custom_border_color`, `VK_EXT_transform_feedback`, `VK_KHR_timeline_semaphore`, `VK_EXT_descriptor_indexing`, etc.).
   - Reportar soporte nativo de texturas ASTC LDR y ETC2/EAC y la ruta de emulación/transcodificación para BC4–BC7.
