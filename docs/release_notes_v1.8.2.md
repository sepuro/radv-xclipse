# RADV Xclipse 540 Release v1.8.2-shadow-fix

**Target Hardware**: Samsung Exynos 1580 (`s5e8855`)  
**GPU Core**: Samsung Xclipse 540 (AMD RDNA 3 / `CHIP_ARIEL`, 2 WGPs / 4 CUs)  
**Android Platform**: Android 14+ (NDK API 34, aarch64)  
**Compilation Profile**: Production Release with `-Db_ndebug=true` (zero debug asserts) and ThinLTO

---

### Shadow & Rasterizer Performance Improvements in v1.8.2

1. **Optimización de Rasterizador y Backface Culling para Sombras (`radv_pipeline_graphics.c` & `radv_cmd_buffer.c`)**:
   - En passes puros de profundidad y mapas de sombras (`color_att_count == 0` con `ds_att.iview != NULL`), se fuerza culling de caras traseras (`cull_mode |= VK_CULL_MODE_BACK_BIT`).
   - Elimina la rasterización redundante de geometría oculta directamente en el hardware rasterizador (PA/SC), aliviando la sobrecarga geométrica sobre los 2 WGPs de la GPU Xclipse 540.
   - Reduce drásticamente el coste de cálculo de primitivas en pases de *Cascaded Shadow Maps* (CSM).

2. **Reutilización de Caché L2 en Passes Repetitivos de Sombras (`radv_cmd_buffer.c`)**:
   - En el `Combined Depth Cache Flush`, se evita la invalidación indiscriminada de toda la caché L2 (`flush_bits &= ~AC_BARRIER_INV_L2`) durante render passes sucesivos de profundidad y sombras.
   - Mantiene calientes las líneas de caché de mapas de sombras ya generados, eliminando caídas bruscas de FPS e inestabilidad al renderizar luces dinámicas.

3. **Ajuste de Subgrupos Wave32 y Presión de Registros VGPR en ACO (`aco_shader_info.c` & `aco_scheduler.cpp`)**:
   - Se implementa `aco_compiler_ariel_tune_vgpr_limit` para acotar el límite de registros VGPR en el scheduler de ACO a 32 registros en Wave32 para shaders de geometría/NGG y fragmentos de sombra.
   - Garantiza una ocupación de 8+ ondas por SIMD en las 4 CUs, previniendo la expulsión (*spilling*) de registros a memoria RAM LPDDR5 del sistema.

4. **Blindaje de Producción y Parche Maestro Unificado (`01-ariel-master-safe.patch`)**:
   - Mantiene activo `-Db_ndebug=true` y ThinLTO (`-Db_lto=true -Db_lto_mode=thin -Dallow-broken-lto=true`).
   - Flags seguros de compilación `-O2 -march=armv8.2-a+dotprod+fp16 -fno-semantic-interposition -fomit-frame-pointer` sin `-ffast-math`.
   - Compatibilidad total de SurfaceFlinger y AHardwareBuffer (`RADEON_SURF_DISABLE_DCC | RADEON_SURF_SCANOUT | RADEON_SURF_MODE_LINEAR_ALIGNED`).
   - Soporte para kernel `sgpu` de Samsung Exynos 1580 en `libdrm` con caché MMR.
