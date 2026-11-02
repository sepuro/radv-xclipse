# RADV Xclipse 540 Release v1.8.3-stable-fps

**Target Hardware**: Samsung Exynos 1580 (`s5e8855`)  
**GPU Core**: Samsung Xclipse 540 (AMD RDNA 3 / `CHIP_ARIEL`, 2 WGPs / 4 CUs)  
**Android Platform**: Android 14+ (NDK API 34, aarch64)  
**Compilation Profile**: Production Release with `-Db_ndebug=true` (zero debug asserts) and ThinLTO

---

### Key Optimizations & Stability Improvements in v1.8.3

1. **Prioridad de Contexto Alta (`AMDGPU_CTX_PRIORITY_HIGH`) en Winsys (`radv_amdgpu_cs.c`)**:
   - Forzado de prioridad de contexto `AMDGPU_CTX_PRIORITY_HIGH` (o `VERY_HIGH` para colas en tiempo real) en la creación de contextos `ac_drm_cs_ctx_create2` para la GPU Xclipse 540 (`CHIP_ARIEL`).
   - Evita de forma efectiva que el kernel driver (`sgpu.ko` / DVFS governor) reduzca las frecuencias de reloj de la GPU durante fotogramas de alta carga computacional o pases geométricos complejos.
   - Cuenta con degradación elegante (*graceful fallback*) a la prioridad original en caso de denegación por directivas restrictivas.

2. **Invalidación Vectorial Selectiva (`RADV_CMD_FLAG_INV_VCACHE`) para Sombras y Profundidad (`radv_cmd_buffer.c`)**:
   - En el `Combined Depth Cache Flush`, se refina el mecanismo de barreras para sustituir la invalidación total de la caché L2 del SoC por invalidación vectorial selectiva (`RADV_CMD_FLAG_INV_VCACHE` / `AC_BARRIER_INV_VMEM`).
   - Elimina el drenado masivo y repetitivo de líneas de caché L2 hacia la memoria del sistema (LPDDR5), previniendo saturación de ancho de banda y caídas de framerate (*micro-stuttering*).
   - Invalida selectivamente la caché de vectores durante la transición y muestreo de mapas de sombras en `radv_barrier`.

3. **Consolidación de Parche Maestro Unificado (`01-ariel-master-safe.patch`)**:
   - Exportación limpia y validada sin rechazos (`git apply --check` verificado al 100%).
   - Preserva todas las mejoras previas: culling optimizado de caras traseras para mapas de sombras, ajuste de VGPRs Wave32 en ACO, anulación de DCC para AHB/scanout, y resolución de direccionamiento MMR en `libdrm`.

4. **Workflow de Compilación de Producción Robusto**:
   - Perfil optimizado con `-Db_ndebug=true` (sin aserciones en runtime).
   - ThinLTO activado para optimizaciones inter-módulos globales.
   - Flags seguros de compilación `-O2 -march=armv8.2-a+dotprod+fp16 -fno-semantic-interposition -fomit-frame-pointer` sin `-ffast-math`.
