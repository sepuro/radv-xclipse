# RADV Xclipse 540 Release v1.8.1-perf

**Target Hardware**: Samsung Exynos 1580 (`s5e8855`)  
**GPU Core**: Samsung Xclipse 540 (AMD RDNA 3 / `CHIP_ARIEL`)  
**Android Platform**: Android 14+ (NDK API 34, aarch64)  
**Compilation Profile**: Production Release with `-Db_ndebug=true` (zero debug asserts) and ThinLTO

---

### Performance Improvements in v1.8.1

1. **Asserts Desactivados (`-Db_ndebug=true`)**:
   - Se asegura la desactivación total de macros de aserción (`assert()`) en tiempo de ejecución en Mesa, ACO y NIR.
   - Elimina la sobrecarga de evaluación de aserciones en el bucle caliente de dibujo de Vulkan, reduciendo drásticamente el *frame-time variance* y stuttering.

2. **ThinLTO y Optimizaciones de Compilador**:
   - Thin Link-Time Optimization (`-Db_lto=true -Db_lto_mode=thin -Dallow-broken-lto=true`).
   - Flags estrictos: `-O2 -march=armv8.2-a+dotprod+fp16 -fno-semantic-interposition -fomit-frame-pointer` sin `-ffast-math` para mantener la exactitud de coma flotante en ACO.

3. **Consolidación del Parche Maestro (`01-ariel-master-safe.patch`)**:
   - Enlace limpio para Gralloc y SurfaceFlinger (`RADEON_SURF_DISABLE_DCC | RADEON_SURF_SCANOUT | RADEON_SURF_MODE_LINEAR_ALIGNED`).
   - Fallback SELinux `/dev/dri/renderD128` y `RADV_DEBUG_NO_HIZ` en `CHIP_ARIEL`.
   - Invalidación de caché vectorial (`RADV_CMD_FLAG_INV_VCACHE | INV_L2`) en transiciones de texturas en `radv_cmd_buffer.c`.
   - Transformación segura a FP16 con `nir_lower_mediump_vars` en shaders Fragment y Compute.
