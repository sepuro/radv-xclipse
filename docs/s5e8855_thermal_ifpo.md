# Gestión de Energía, Sincronización Térmica e IFPO: Samsung Exynos 1580 (Xclipse 540 / CHIP_ARIEL / MGFX2)

Este documento detalla el funcionamiento del subsistema de control de energía del kernel `sgpu.ko`, los mecanismos de apagado inter-cuadro (**IFPO - Inter-Frame Power Off**), las banderas de prioridad de contexto y los parámetros de sincronización en `drmIoctl` extraídos mediante desensamblado e ingeniería inversa de `ref_decompiled/`.

---

## 1. IFPO (Inter-Frame Power Off) en el Kernel `sgpu.ko`

El hardware gráfico Samsung Xclipse 540 (MGFX2, arquitectura AMD RDNA 3 para Exynos 1580 / `s5e8855`) implementa **IFPO** a nivel de silicio para suspender el suministro eléctrico y el reloj de los Shader Cores / WGPs entre fotogramas sucesivos cuando la GPU finaliza su carga de trabajo.

### 1.1 Módulos y Puntos de Entrada Clave
- **Fichero Fuente Original**: `../exynos/external-modules/sgpu/sgpu/sgpu_ifpo.c`
- **Funciones Principales en `.text` de `sgpu.ko`**:
  - `sgpu_ifpo_init` (`0x0652c0`): Inicialización del subsistema IFPO.
  - `sgpu_ifpo_enable` (`0x065410`): Activación de la máquina de estados IFPO.
  - `sgpu_ifpo_lock` (`0x065500`): Bloqueo de entrada en IFPO al despachar un trabajo (`amdgpu_job_submit` @ `0x05768c`).
  - `sgpu_ifpo_unlock` (`0x0655a8`): Desbloqueo y decremento del refcount de actividad (`amdgpu_job_free_cb` @ `0x0581cc`).
  - `__sgpu_ifpo_abort_power_off` (`0x06679c`): Rutina crítica de corte de alimentación (Power Gating de Shader Cores).
  - `__sgpu_ifpo_abort_power_on` (`0x0663fc`): Rutina de reactivación rápida mediante PMU (`dbg_snapshot_pmu`).

### 1.2 Condición de Hardware para Entrada en IFPO (`CP_PERFMON_CNTL`)
- **Registro Hardware**: `R_036020_CP_PERFMON_CNTL` (Dirección MMIO `0x036020`).
- **Comportamiento en Silicio**:
  - Si los bits `[7:0]` de `CP_PERFMON_CNTL` son distintos de cero (`STOP_COUNTING` = `0x02`), la unidad de gestión de energía del hardware rechaza el paso a suspensión y genera un timeout en el PMU (`GPUPWRACK timeout! BG3D_PWRCTL_STATUS = %#010x`), bloqueando el núcleo de CPU en espera activa.
  - Cuando los bits `[7:0]` están a `0x00` (`DISABLE_AND_RESET` = `0x00`), el hardware ejecuta `__sgpu_ifpo_abort_power_off` de manera limpia en menos de 10 microsegundos, reduciendo el consumo pasivo de los WGPs a menos de 50 mW durante pausas entre fotogramas.

### 1.3 Control Dinámico de WGPs (`amdgpu_wgp_gating_ioctl`)
- **IOCTL**: Opcode `0x5e` (Número real `0x9e`, tamaño `0x44` = 68 bytes) en `amdgpu_ioctls_kms`.
- **Estructura C**:
  ```c
  struct amdgpu_wgp_gating {
      uint32_t op;       // 1 = set mask, 2 = reset, 3 = get telemetry
      uint32_t pad;
      uint64_t value;    // Máscara de WGPs activos (0x03 para 2 WGPs en Exynos 1580)
      uint8_t  telemetry[56];
  };
  ```

---

## 2. Banderas DRM IOCTL de Prioridad de Contexto y DVFS

### 2.1 Fijación de Reloj GPU / DVFS Boost (`sgpu_driver_control_ioctl`)
- **IOCTL**: Opcode `0x5b` (Número real `0x9b`, tamaño `0x18` = 24 bytes).
- **Dirección en `.text`**: `0x0098f8`.
- **Valores Hexadecimales**:
  - `cmd`: `0x00000000` (stricto sensu u32 = 0).
  - `val`: `0x0000000000000001` (1 = Activar DVFS Performance Lock para 3D; 0 = Retornar a gobernador pasivo).

### 2.2 Prioridades del Scheduler AMDGPU (`amdgpu_ctx_ioctl`)
- **IOCTL**: Opcode `0x02` (Número real `0x42`).
- **Valores Hexadecimales de Prioridad**:
  - `AMDGPU_CTX_PRIORITY_LOW`       = `0x00000000` (0)
  - `AMDGPU_CTX_PRIORITY_NORMAL`    = `0x000001F4` (500 decimal)
  - `AMDGPU_CTX_PRIORITY_HIGH`      = `0x000003E8` (1000 decimal - Cargas 3D prioritarias)
  - `AMDGPU_CTX_PRIORITY_VERY_HIGH` = `0x000005DC` (1500 decimal - Tiempo real)

---

## 3. Sincronización Térmica y Eliminación de Spin-Waits de CPU

En la pila Vulkan estándar sobre Android, esperas activas con `sched_yield()` en `vkWaitForFences` o consultas de syncobjs mantienen los núcleos de rendimiento ARM Cortex-A720 al 100% de uso de CPU, disipando calor innecesario y provocando thermal throttling en el SoC.

### 3.1 Llamadas DRM Syncobj del Kernel
- **`DRM_IOCTL_SYNCOBJ_WAIT`**: Opcode `0x83` / `0xC3` (`_IOWR('d', 0xC3, struct drm_syncobj_wait)`).
- **`DRM_IOCTL_SYNCOBJ_TIMELINE_WAIT`**: Opcode `0x8a` / `0xC6` (`_IOWR('d', 0xC6, struct drm_syncobj_timeline_wait)`).
- **Banderas de Espera**:
  - `DRM_SYNCOBJ_WAIT_FLAGS_WAIT_ALL`        = `0x01` (`1 << 0`)
  - `DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT` = `0x02` (`1 << 1`)
  - `DRM_SYNCOBJ_WAIT_FLAGS_WAIT_AVAILABLE`  = `0x04` (`1 << 2`)

### 3.2 Timeouts de Sincronización en `vkQueuePresentKHR` y `vkWaitForFences`
- **Valores Extraídos**:
  - Timeout de cuadro estándar (60 FPS): `16,666,666 ns` (`0x00FE502A`).
  - Timeout de cuadro a 30 FPS: `33,333,333 ns` (`0x01FCA055`).
  - Timeout de exportación de señal sync_file: `3,000,000,000 ns` (`0xB2D05E00` = 3s).
  - Timeout infinito (`UINT64_MAX`): `0xFFFFFFFFFFFFFFFFULL`.
- **Estrategia Térmica Adoptada**:
  - Forzar que las esperas pasen directamente por `DRM_IOCTL_SYNCOBJ_WAIT` o `DRM_IOCTL_SYNCOBJ_TIMELINE_WAIT` con `DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT` (`0x02`).
  - Esto pone al hilo en estado `TASK_INTERRUPTIBLE` en el planificador del kernel Linux, apagando los relojes del hilo de CPU hasta que la GPU genera una interrupción de fin de ejecución (IRQ). La utilización de CPU pasa del 100% al 0%, eliminando el sobrecalentamiento en las esperas.
